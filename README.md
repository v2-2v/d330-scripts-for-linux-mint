# d330-scripts-for-linux-mint

Small, independent, userspace-only scripts and fixes for running Linux
Mint (Cinnamon) on the Lenovo IdeaPad D330-10IGM — the kind of thing
that's too small to be its own repo, but doesn't belong bundled into one
big undifferentiated pile either. Each subdirectory is a self-contained
fix: its own README, its own install steps, usable independently of the
others.

**Kernel-level fixes live in a separate repo:**
[linux_lenovod330](https://github.com/v2-2v/linux_lenovod330) — a DKMS
patch that avoids the D330's known black-screen-after-suspend/DPMS bug by
controlling the backlight GPIO independently of the panel power cycle.
Background on the underlying hardware bug (kernel/GOP/Windows-driver
comparison, VBT bytecode decoding, board schematic analysis) is written up
there and on
[Qiita](https://qiita.com/v2-2v/items/5a0f0b72e93312a4a026) (Japanese).
Everything in *this* repo is plain userspace configuration/scripting —
nothing here touches the kernel or requires a reboot into a custom build
(the login fix does restart lightdm, but that's it).

## What's here

- [`login-backlight-only-fix/`](login-backlight-only-fix/) — fixes the
  screen sometimes coming up backlight-only right at the login→desktop
  transition. Same underlying panel bug as the suspend/DPMS one above,
  triggered instead by Cinnamon auto-rotating the display on session
  start. Fix: make the lightdm greeter apply the same rotation first, so
  no orientation change (and thus no modeset) happens at login.
- [`accelerometer-flip/`](accelerometer-flip/) — flips the screen (and
  touch input) 180 degrees based on the built-in accelerometer, right-side
  up vs. upside down only — no full 4-way auto-rotate, since Cinnamon
  doesn't support that natively on this panel and every rotation here is a
  modeset that risks the same underlying bug.

## Environment

- Model: Lenovo IdeaPad D330-10IGM
- OS: Linux Mint 22.3 (Cinnamon, X11, lightdm + lightdm-gtk-greeter)

Likely applies to the D330-10IGL and similar Bay Trail/Cherry
Trail/Gemini Lake DSI tablets too, but this is the only combination
actually verified.

## License

BSD-3-Clause (see `LICENSE`), unless a subdirectory says otherwise.

## Disclaimer

Provided as-is from a personal hardware investigation, no warranty, no
affiliation with Lenovo or Intel. See each subdirectory's README for
specific risk notes (e.g. the login fix restarts your display manager;
the accelerometer flip triggers real display modesets on every physical
flip).
