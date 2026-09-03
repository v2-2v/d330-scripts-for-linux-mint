#!/bin/sh
# D330: rotate the greeter's Xorg output to match what Cinnamon (muffin)
# will apply anyway via the kernel's "panel orientation: Right Side Up"
# connector property. Without this, the greeter shows native portrait and
# Cinnamon rotates on session start, which forces a real DSI modeset --
# the same unreliable re-init path as DPMS/suspend.
xrandr --output DSI1 --rotate right
