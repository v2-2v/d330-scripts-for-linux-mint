# D330: 180-degree screen flip from the accelerometer (up/down only)

A minimal, deliberately narrow-scope auto-rotate script for the Lenovo
IdeaPad D330-10IGM: flips the screen (and touch input) 180 degrees based
on the built-in accelerometer, and does *nothing else* — no full 4-way
rotation, no portrait mode.

## Why so narrow?

Any screen rotation via `xrandr` is a real DRM modeset. On this panel,
modesets are what trigger the well-documented, probabilistically-unreliable
DSI re-init bug covered in
[linux_lenovod330](https://github.com/v2-2v/linux_lenovod330) (suspend/DPMS)
and
[linux_lenovod330-linuxmint-login-backlight-only-fix](https://github.com/v2-2v/linux_lenovod330-linuxmint-login-backlight-only-fix)
(login). A full auto-rotate implementation would mean every physical tilt
of the device is another roll of that dice. This script only reacts to two
of the four sensor states — the 180-degrees-apart pair that corresponds to
"right side up" vs. "upside down" while using the device as a laptop — and
ignores the other two (which correspond to true portrait orientations of
the panel's native mode, not a meaningful state for normal laptop use).
That keeps the number of modesets, and therefore the exposure to the
underlying bug, as low as reasonably possible for this specific need.

## Background: does Linux Mint/Cinnamon support this natively?

No — not out of the box, at least not on Mint 22.3. There's a leftover
gsettings key, `org.cinnamon.settings-daemon.peripherals.touchscreen
orientation-lock`, but no `org.cinnamon.settings-daemon.plugins.orientation`
schema and no process actually consuming it. The setting is a vestige with
nothing behind it; flipping it does nothing.

The accelerometer itself works fine, though. At the kernel level:

```
$ cat /sys/bus/iio/devices/iio:device0/name
BMA253/BMA254/BMA255/BMC150/BMC156/BMI055
$ cat /sys/bus/iio/devices/iio:device0/in_accel_x_raw
-31
```

And via `iio-sensor-proxy` (the system D-Bus service that turns raw
accelerometer data into an orientation string):

```
$ gdbus call --system --dest net.hadess.SensorProxy \
    --object-path /net/hadess/SensorProxy \
    --method org.freedesktop.DBus.Properties.GetAll net.hadess.SensorProxy
({'HasAccelerometer': <true>, 'AccelerometerOrientation': <'left-up'>, ...},)
```

So the sensor pipeline is solid; there's just no rotation logic consuming
it on this desktop environment. This script is that missing piece, scoped
down to what's actually useful (and safe-ish) here.

This started from [gitHideaki's Qiita
article](https://qiita.com/gitHideaki/items/609aef11e68175d1a0cd) on
building a similar setup for a Lenovo YOGA 900 — full 4-way rotation via a
Python wrapper around `monitor-sensor` + `xrandr` + `xinput`, autostarted
via Cinnamon's Startup Applications (the author noted a `systemd` daemon
approach didn't work for them). The approach here follows the same shape,
narrowed in scope for the reasons above.

## The orientation mapping is panel-specific — verify yours

`monitor-sensor` reports one of four states: `normal`, `bottom-up`,
`left-up`, `right-up`. Naively, you'd expect `normal`/`bottom-up` to be the
"right side up / upside down" pair. **On this panel it's the other pair.**
This D330's native panel mode is portrait (`800x1280`); the desktop is
shown rotated via an `ACCEL_MOUNT_MATRIX` udev hwdb quirk plus the DSI-1
connector's `panel orientation: Right Side Up` kernel property (see
[linux_lenovod330-linuxmint-login-backlight-only-fix](https://github.com/v2-2v/linux_lenovod330-linuxmint-login-backlight-only-fix)
for the full story on that property). `normal`/`bottom-up` line up with the
*native portrait* orientation, not the rotated landscape one this device
is normally used in — so the pair that actually matters for "which way is
up while using this as a laptop" turns out to be `right-up`/`left-up`
instead.

This was confirmed empirically on real hardware: tilting the device one
way read as `right-up` (screen already correct, matching the default
rotation), tilting it 180 degrees the other way read as `left-up`.
**If you're adapting this for a different unit or panel, verify your own
mapping** — run `monitor-sensor` in a terminal on the physical device (see
below for why it has to be local, not SSH) and tilt it both ways before
trusting which pair means what.

## Install

```bash
git clone https://github.com/v2-2v/d330-scripts-for-linux-mint.git
cd d330-scripts-for-linux-mint/accelerometer-flip

sudo install -m 755 scripts/d330-auto-rotate.sh /usr/local/bin/d330-auto-rotate.sh
mkdir -p ~/.config/autostart
install -m 644 scripts/d330-auto-rotate.desktop ~/.config/autostart/d330-auto-rotate.desktop
```

Takes effect on your next login. `scripts/d330-auto-rotate.sh`:

```sh
#!/bin/bash
TOUCH_DEV="Goodix Capacitive TouchScreen"
OUTPUT="DSI1"

apply_normal() {
  xrandr --output "$OUTPUT" --rotate right
  xinput set-prop "$TOUCH_DEV" 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
}

apply_flipped() {
  xrandr --output "$OUTPUT" --rotate left
  xinput set-prop "$TOUCH_DEV" 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1
}

state=normal
monitor-sensor 2>&1 | while read -r line; do
  case "$line" in
    *"orientation changed: right-up"*)
      [ "$state" = normal ] || { apply_normal; state=normal; }
      ;;
    *"orientation changed: left-up"*)
      [ "$state" = flipped ] || { apply_flipped; state=flipped; }
      ;;
  esac
done
```

`scripts/d330-auto-rotate.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=D330 Auto Rotate (right-up/left-up only)
Comment=Flips the D330 screen 180 degrees based on the accelerometer; only reacts to right-up/left-up, ignores normal/bottom-up
Exec=/usr/local/bin/d330-auto-rotate.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
```

`TOUCH_DEV` is this unit's touchscreen name from `xinput list` (`Goodix
Capacitive TouchScreen`) — check yours if it differs.

## Why XDG autostart, not systemd

`monitor-sensor` (and therefore this script) needs to call
`iio-sensor-proxy`'s `ClaimAccelerometer` over D-Bus, which is
polkit-gated. That authorization check appears to require the calling
process to actually belong to the active graphical session on the seat
(`seat0`) — not just have the right `DISPLAY`/`XAUTHORITY` environment
variables. A process launched over SSH, even with those set correctly,
belongs to its own SSH session and gets rejected:

```
WARNING: Failed to claim accelerometer: GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: Not Authorized: Sensor claim not allowed
```

This is why all testing for this specific feature had to happen in a
terminal opened on the physical device itself, unlike everything else in
the sibling repos (which was doable entirely over SSH). It also lines up
with the Qiita article author's report that a `systemd` daemon didn't work
for them — XDG autostart runs as part of the session's own startup, so it
should already be correctly associated with the seat. (Untested: whether a
`systemd --user` service *can* work if started late enough / tagged
correctly — XDG autostart was confirmed working, so that avenue wasn't
pursued further.)

## Verification status

- ✅ Sensor data confirmed live and correct (`iio-sensor-proxy`,
  kernel IIO raw values).
- ✅ Confirmed on real hardware: physically flipping the device 180 degrees
  correctly flips both the display and touch input, using the
  `right-up`/`left-up` mapping above.
- ❓ Not yet statistically verified whether repeated flips ever trigger the
  underlying black-screen bug — a handful of manual flips during testing
  didn't, but that's a small sample against a probabilistic failure mode.

## Related

- [linux_lenovod330](https://github.com/v2-2v/linux_lenovod330) — the
  backlight-only GPIO fix for the suspend/DPMS black-screen bug.
- [linux_lenovod330-linuxmint-login-backlight-only-fix](https://github.com/v2-2v/linux_lenovod330-linuxmint-login-backlight-only-fix)
  — the same underlying bug, triggered at login instead; also where the
  `panel orientation` kernel property referenced above is explained in
  detail.

(This document is a personal investigation log, not an official statement
from Lenovo or Intel.)
