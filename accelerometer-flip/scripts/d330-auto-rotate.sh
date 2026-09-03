#!/bin/bash
# D330: physical-sensor-based up/down screen flip only.
# Reacts only to "right-up" (our normal baseline, screen readable as
# currently set up) and "left-up" (180 degrees opposite); "normal"/
# "bottom-up" (the other pair -- true portrait orientations of the native
# panel) are ignored on purpose, so ordinary handling doesn't trigger a
# rotation. Empirically confirmed on real hardware: tilting right reads
# correctly as "right-up" (matches default), tilting left (180 degrees
# from that) reads as "left-up".
#
# WARNING: each xrandr rotation here is a real DRM modeset, which
# re-triggers the same probabilistically-unreliable DSI re-init path
# documented in https://github.com/v2-2v/linux_lenovod330 -- physically
# flipping the device risks a black screen, same as suspend/DPMS/login.
# Scope is deliberately narrowed to only the two states above to keep
# that exposure as low as possible.

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
  echo "$line"
  case "$line" in
    *"orientation changed: right-up"*)
      [ "$state" = normal ] || { apply_normal; state=normal; }
      ;;
    *"orientation changed: left-up"*)
      [ "$state" = flipped ] || { apply_flipped; state=flipped; }
      ;;
  esac
done
