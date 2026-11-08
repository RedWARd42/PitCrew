#!/usr/bin/env bash
# Usage: scripts/dump_ui.sh out.xml  -- dumps the current UI tree via uiautomator.
set -e
export MSYS_NO_PATHCONV=1
OUT=${1:-ui.xml}
adb shell uiautomator dump /sdcard/ui.xml >/dev/null
adb exec-out cat /sdcard/ui.xml > "$OUT"
echo "wrote $OUT"
