#!/bin/bash
# Persistent outer monitor. Run once via Claude Monitor tool.
# Detects CrafterTech launches, runs the inner monitor while the window is open,
# then goes back to watching for the next launch. Never needs to be restarted.

ROOT="C:/Users/404Tr/OneDrive/Documents/Game Engine/tools/crafter_tech"
LAUNCH_F="$ROOT/launch_ts.txt"
PID_F="$ROOT/window.pid"
MONITOR="$ROOT/monitor.sh"

LAST_LAUNCH_TS=0

echo "AUTO_MONITOR_READY"

while true; do
  if [ -f "$LAUNCH_F" ]; then
    TS=$(cat "$LAUNCH_F" 2>/dev/null | tr -d '[:space:]')
    TS=${TS:-0}
    if [ "$TS" != "$LAST_LAUNCH_TS" ] && [ "$TS" != "0" ]; then
      LAST_LAUNCH_TS=$TS
      echo "CRAFTER_LAUNCHED ts=$TS"
      bash "$MONITOR"
      echo "CRAFTER_CLOSED"
    fi
  fi
  sleep 1
done
