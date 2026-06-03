#!/bin/bash
# Fires NODE_SELECTED, SIM_ISSUES_REPORTED, GENERATE_FRAMEWORK events.
# Exits automatically when the CrafterTech window closes.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$ROOT/state.json"
PID_F="$ROOT/window.pid"

LAST_REQ_TS=0
LAST_SIM_TS=0
LAST_GEN_TS=0

echo "MONITOR_START"

# Wait up to 8s for window.pid to appear before entering the main loop
for i in $(seq 1 16); do
  [ -f "$PID_F" ] && break
  sleep 0.5
done

while true; do
  # Exit only when pid file disappears (window.ps1 deletes it on close)
  if [ ! -f "$PID_F" ]; then
    echo "WINDOW_CLOSED"
    exit 0
  fi

  if [ -f "$STATE" ]; then
    # SEC-04: Read values and sanitise before echoing (strip chars outside safe set)
    REQ_TS=$(grep -o '"request_ts":[0-9]*' "$STATE" | grep -o '[0-9]*')
    SIM_TS=$(grep -o '"sim_issues_ts":[0-9]*' "$STATE" | grep -o '[0-9]*')
    GEN_TS=$(grep -o '"generate_ts":[0-9]*' "$STATE" | grep -o '[0-9]*')
    NODE=$(grep -o '"selected_node":"[^"]*"' "$STATE" | sed 's/.*":"//;s/"//' | tr -cd 'a-zA-Z0-9_-')
    REQUEST=$(grep -o '"request":"[^"]*"' "$STATE" | sed 's/.*":"//;s/"//' | tr -cd 'a-zA-Z0-9 _-')

    REQ_TS=${REQ_TS:-0}
    SIM_TS=${SIM_TS:-0}

    if [ "$REQ_TS" != "$LAST_REQ_TS" ] && [ "$REQ_TS" != "0" ]; then
      LAST_REQ_TS=$REQ_TS
      echo "NODE_SELECTED ts=$REQ_TS node=$NODE request=$REQUEST"
    fi

    if [ "$SIM_TS" != "$LAST_SIM_TS" ] && [ "$SIM_TS" != "0" ]; then
      LAST_SIM_TS=$SIM_TS
      echo "SIM_ISSUES_REPORTED ts=$SIM_TS"
    fi

    # BUG-04: Skip comparison if GEN_TS is empty (file read during write gap)
    if [ -z "$GEN_TS" ]; then
      sleep 0.5
      continue
    fi
    if [ "$GEN_TS" != "$LAST_GEN_TS" ] && [ "$GEN_TS" != "0" ]; then
      LAST_GEN_TS=$GEN_TS
      echo "GENERATE_FRAMEWORK ts=$GEN_TS"
    fi
  fi

  sleep 0.5
done
