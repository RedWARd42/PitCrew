#!/usr/bin/env bash
# usage: scripts/e2e.sh <scenario> [timeout_s=25]. Needs emulator + app running. Exit 0 = verdict matches expect.
set -u
S=${1:?scenario id}; T=${2:-25}
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
mkdir -p "$ROOT/eval/screens"
EXPECT=$(python -c "import yaml,sys;print(yaml.safe_load(open('scenarios/$S.yaml'))['expect']['verdict'])") || exit 2
SENDER=$(python -c "import yaml;print(yaml.safe_load(open('scenarios/$S.yaml'))['sender'])")
adb logcat -c
LOG=$(mktemp); adb logcat -s SWARM:D > "$LOG" 2>&1 & LP=$!
trap 'kill $LP 2>/dev/null; rm -f "$LOG"' EXIT
python scripts/inject.py "$S" || exit 2
# open the thread in the default SMS app (Google Messages)
adb shell am start -a android.intent.action.SENDTO -d "sms:$SENDER" >/dev/null 2>&1
GOT=""; for _ in $(seq "$T"); do
  GOT=$(grep -o 'scan_complete.*' "$LOG" | tail -1); [ -n "$GOT" ] && break; sleep 1
done
sleep 1; adb exec-out screencap -p > "$ROOT/eval/screens/$S.png"
if [ -z "$GOT" ]; then echo "FAIL $S: no scan_complete within ${T}s (screen saved)"; exit 1; fi
RISK=$(echo "$GOT" | sed -n 's/.*risk=\([0-9]*\).*/\1/p')
V=$(echo "$GOT" | sed -n 's/.*verdict=\([a-z]*\).*/\1/p')
if [ -z "$V" ]; then  # log only carries risk; map with the thresholds below (tune to backend)
  if   [ "${RISK:-0}" -ge 70 ]; then V=scam; elif [ "${RISK:-0}" -ge 40 ]; then V=suspicious
  elif [ "${RISK:-0}" -ge 20 ]; then V=unsure; else V=safe; fi
fi
OK=0; [ "$V" = "$EXPECT" ] && OK=1
[ "$EXPECT" = scam ] && [ "$V" = suspicious ] && OK=1   # suspicious counts as a catch for scam scenarios
[ $OK = 1 ] && { echo "PASS $S: $V (risk=$RISK) expected $EXPECT"; exit 0; }
echo "FAIL $S: $V (risk=$RISK) expected $EXPECT"; exit 1
