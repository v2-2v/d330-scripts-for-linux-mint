# D330 Linux Mint: backlight-only screen at login, and a fix

## TL;DR

- On Lenovo IdeaPad D330-10IGM + Linux Mint 22.3 (Cinnamon), the screen can
  come up **backlight-only (no image) right at the moment you log in** —
  going from the lightdm greeter into the Cinnamon desktop.
- Root cause: **the same underlying bug** as the [suspend/DPMS black-screen
  bug](https://github.com/v2-2v/linux_lenovod330) on this panel — just
  triggered differently. The greeter reuses the BIOS-handed-off display
  state (`fastset`), which is safe. But Cinnamon's window manager (muffin)
  auto-rotates the screen once at session start, and *that* forces a real
  modeset — the first time i915's own (probabilistically unreliable) DSI
  re-init code actually runs.
- Fix: make the greeter apply the **same rotation up front** (via lightdm's
  `display-setup-script` hook), so there's no orientation *change* — and
  therefore no modeset — at the login→desktop transition. Confirmed: the
  greeter now shows landscape. Whether this measurably reduces the
  black-screen rate hasn't been statistically verified yet.
- **Independent of the [linux_lenovod330](https://github.com/v2-2v/linux_lenovod330)
  DKMS patch** (which targets suspend/DPMS) — this issue reproduces on a
  completely stock, unmodified kernel, and this fix works standalone or
  alongside that other repo.

---

## Environment

- Model: Lenovo IdeaPad D330-10IGM
- OS: Linux Mint 22.3 (Cinnamon, X11, lightdm + lightdm-gtk-greeter)
- Kernel: `7.0.0-30-generic` (stock, unmodified)
- GPU: Intel Gemini Lake, UHD Graphics 600
- Internal display: DSI-1, native physical panel mode `800x1280@60` (portrait)

## Symptom

- The lightdm greeter (login screen) displays fine — in **portrait**.
- Logging in and transitioning to the Cinnamon desktop, the screen
  sometimes comes up **backlight-only** — no image (not every time;
  probabilistic).
- When it happens, logging in again or rebooting usually recovers it (same
  as the [suspend bug](https://github.com/v2-2v/linux_lenovod330) — a real
  power cycle reliably works).

## Root-cause diagnosis

The first thing that stood out: the greeter and the desktop are in
**different orientations** (greeter = portrait, desktop = landscape).

```bash
$ xrandr --verbose
DSI1 connected primary 1280x800+0+0 (0x47) right (normal left inverted right x axis y axis) 135mm x 216mm
...
	panel orientation: Right Side Up
		supported: Normal, Upside Down, Left Side Up, Right Side Up
...
  800x1280 (0x47) 78.500MHz -HSync -VSync *current +preferred
```

The key detail is `panel orientation: Right Side Up` — a **DRM connector
property from the kernel (i915)** itself. It's derived from VBT data saying
"this panel is physically mounted rotated 90°"; the native mode stays
`800x1280` (portrait), and the display server is expected to read this
property and apply a compensating rotation automatically.

To narrow it down further, checked:

- `~/.config/monitors.xml`: doesn't exist (not a saved per-user layout)
- `/etc/X11/xorg.conf.d/`: no static rotation config
- `org.cinnamon.settings-daemon.peripherals.touchscreen orientation-lock`:
  `true` (rules out dynamic accelerometer-based auto-rotate)
- Xorg log: `intel_drv.so` (the legacy `intel` driver) is loaded

**Conclusion**: it's **Cinnamon's window manager, muffin** (a Mutter fork)
that actually reads the `panel orientation` property and applies the
compensating rotation — once, at session start. The lightdm greeter
(`lightdm-gtk-greeter`, a plain X11 client, not a Mutter-based compositor)
has no such logic, so it stays in the raw native portrait orientation.

In other words:

```
[greeter starts]                      [login -> Cinnamon starts]
state: 800x1280, no rotation          state: 800x1280, no rotation
(still the BIOS-handed-off       ->   muffin issues xrandr --rotate right
 fastset state)                             |
                                       real modeset happens
                                             |
                                       fastset is invalidated; i915's own
                                       DSI re-init code runs for the
                                       first time
                                             |
                                       fails probabilistically (known bug)
```

This is **exactly the same code path** as the [suspend/DPMS black-screen
bug](https://github.com/v2-2v/linux_lenovod330) — i915's
`intel_dsi_disable()` → `intel_dsi_pre_enable()`, which re-toggles the
panel power/reset GPIOs and re-establishes the DSI protocol — just
triggered by "the first modeset after login (a rotation change)" instead
of "resuming from suspend."

## The fix

The underlying i915 bug itself can't be fixed (same conclusion as the
[other repo](https://github.com/v2-2v/linux_lenovod330)), so this instead
avoids the *trigger*: the modeset itself. Specifically, have the greeter
apply the same rotation Cinnamon will apply anyway, before it even draws —
so the state stays consistent all the way from greeter to desktop, and no
modeset happens at login at all.

`display-setup-script` runs, as root, right after the greeter's X server
comes up but **before** the greeter starts drawing. Running
`xrandr --rotate right` there means the greeter itself starts out already
in landscape.

### Install (copy-paste)

```bash
git clone https://github.com/v2-2v/linux_lenovod330-linuxmint-login-backlight-only-fix.git
cd linux_lenovod330-linuxmint-login-backlight-only-fix

sudo install -m 755 scripts/d330-lightdm-rotate.sh /etc/lightdm/d330-lightdm-rotate.sh
sudo install -m 644 scripts/90-d330-rotate.conf /etc/lightdm/lightdm.conf.d/90-d330-rotate.conf

sudo reboot
```

`scripts/d330-lightdm-rotate.sh`:

```sh
#!/bin/sh
# D330: rotate the greeter's Xorg output to match what Cinnamon (muffin)
# will apply anyway via the kernel's "panel orientation: Right Side Up"
# connector property. Without this, the greeter shows native portrait and
# Cinnamon rotates on session start, which forces a real DSI modeset --
# the same unreliable re-init path as DPMS/suspend.
xrandr --output DSI1 --rotate right
```

`scripts/90-d330-rotate.conf`:

```ini
[Seat:*]
display-setup-script=/etc/lightdm/d330-lightdm-rotate.sh
```

Rebooting restarts lightdm, so any existing session is lost — same caveat
as any other display-manager-affecting change.

### Removing it

```bash
sudo rm -f /etc/lightdm/d330-lightdm-rotate.sh /etc/lightdm/lightdm.conf.d/90-d330-rotate.conf
sudo reboot
```

## Verification status

- ✅ **Confirmed**: after applying this, the greeter now displays in
  landscape.
- ❓ **Not yet verified**: whether the login→desktop transition still
  triggers some equivalent internal processing (or whether keeping the
  greeter and desktop state identical actually makes it less likely to
  fail) can't be judged from a handful of tries. Per the findings from the
  [suspend-bug investigation](https://github.com/v2-2v/linux_lenovod330)
  (a probabilistic hardware-margin issue whose success rate varies a lot
  by conditions), confirming this statistically will need many login
  attempts.

## Relation to `linux_lenovod330`

Same model, same underlying root cause (the structural weakness of
GeminiLake + i915 + a VBT-driven DSI panel, where the panel's power/init
sequence fails probabilistically) — but a different mitigation approach for
a different trigger:

| | Trigger | Fix |
|---|---|---|
| [linux_lenovod330](https://github.com/v2-2v/linux_lenovod330) | Resuming from suspend, or DPMS off/on | Kernel patch: control the backlight GPIO independently, so the panel power cycle is never touched at all |
| This document | Auto-rotation on the login→desktop transition | Align the greeter's rotation with the desktop's, so no modeset happens at login |

Both are "avoid the trigger" fixes rather than "fix the bug itself." **This
fix works standalone on a completely stock kernel**, and is safe to use
alongside the `linux_lenovod330` DKMS patch.

## Future work

- Run dozens of login attempts to statistically confirm whether the
  black-screen rate actually dropped after this fix.
- If it still happens, capture login-time logs with `drm.debug=0x1e` and
  check whether `Starting MIPI sequence` still appears (i.e. whether a
  modeset is still occurring somehow).
- Consider switching to a greeter that natively respects the `panel
  orientation` property (e.g. a Mutter/GNOME-Shell-based greeter) as a more
  fundamental alternative.

(This document is a personal investigation log, not an official statement
from Lenovo or Intel.)
