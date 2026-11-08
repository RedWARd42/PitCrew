#!/usr/bin/env bash
# Enable the Signal Swarm accessibility service on the connected emulator/device via adb.
# Usage: scripts/enable_service.sh [disable]
# Notes: on API 33+ a sideloaded (adb install) app is "restricted" for accessibility; for debug installs via adb
# this normally works with `settings put`. If Settings greys the toggle out, run:
#   adb shell cmd appops set com.example.signal_swarm ACCESS_RESTRICTED_SETTINGS allow

export MSYS_NO_PATHCONV=1
SVC=com.example.signal_swarm/com.example.signal_swarm.SwarmAccessibilityService
adb shell cmd appops set com.example.signal_swarm ACCESS_RESTRICTED_SETTINGS allow 2>/dev/null || true
CUR=$(adb shell settings get secure enabled_accessibility_services | tr -d '\r')
[ "$CUR" = "null" ] && CUR=""
CUR=$(echo "$CUR" | tr ':' '\n' | grep -v -x -F "$SVC" | grep -v '^$' | paste -sd: - || true)
if [ "$1" = "disable" ]; then NEW="$CUR"; else NEW="${CUR:+$CUR:}$SVC"; fi
adb shell settings put secure enabled_accessibility_services "$NEW"
adb shell settings put secure accessibility_enabled 1
echo "enabled_accessibility_services=$(adb shell settings get secure enabled_accessibility_services)"
