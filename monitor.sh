#!/bin/bash
# Fires NODE_SELECTED, SIM_ISSUES_REPORTED, GENERATE_CHASSIS events.
# Exits automatically when the CrafterTech window closes (or fails to start,
# or crashes leaving a stale pid file behind).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$ROOT/state.json"
PID_F="$ROOT/window.pid"

LAST_REQ_TS=0
LAST_SIM_TS=0
LAST_GEN_TS=0
LAST_SYNC_TS=0
LAST_REIMPORT_TS=0
LAST_GDD_EXPORT_TS=0

echo "MONITOR_START"

# FIX (premature-close on slow startup): wait up to 60s for window.pid to
# appear. Do NOT fall through into the main loop without having seen it —
# treating "not present yet" as "closed" killed monitoring for the whole
# session on slower machine starts. If it truly never appears, report a
# distinct MONITOR_TIMEOUT (not WINDOW_CLOSED) so the failure is diagnosable.
SEEN_PID=0
for i in $(seq 1 120); do
  if [ -f "$PID_F" ]; then SEEN_PID=1; break; fi
  sleep 0.5
done
if [ "$SEEN_PID" -eq 0 ]; then
  echo "MONITOR_TIMEOUT"
  exit 0
fi

# FIX (crash recovery, mirrors get_decision.ps1's Get-Process check): a stale
# window.pid left behind by a crash/force-kill (FormClosing only removes it on
# a graceful exit — window.ps1:1846) must not be mistaken for a live window.
is_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] || return 1
  tasklist //FI "PID eq $pid" 2>/dev/null | grep -q "[[:space:]]$pid[[:space:]]"
}

LIVENESS_COUNTER=0

while true; do
  if [ ! -f "$PID_F" ]; then
    echo "WINDOW_CLOSED"
    exit 0
  fi

  # Throttle the liveness check: `tasklist` costs ~130ms per call (a full
  # process-table enumeration). Running it every 0.5s poll would burn a
  # subprocess 7200x/hour for a rare event (crash leaving a stale pid file).
  # The cheap file-existence check above already covers the common graceful-
  # close path; recheck liveness once every ~5s — still fast enough recovery.
  LIVENESS_COUNTER=$((LIVENESS_COUNTER + 1))
  if [ "$LIVENESS_COUNTER" -ge 10 ]; then
    LIVENESS_COUNTER=0
    PID=$(tr -cd '0-9' < "$PID_F" 2>/dev/null)
    if ! is_pid_alive "$PID"; then
      echo "WINDOW_CLOSED"
      exit 0
    fi
  fi

  if [ -f "$STATE" ]; then
    # FIX (torn-read race): snapshot the file ONCE per poll so request_ts,
    # selected_node and request always come from the same atomic write —
    # window.ps1 writes them together (window.ps1:1184-1193) and reading them
    # via 5 separate `grep` invocations let a concurrent Move-Item swap the
    # file mid-poll, producing events whose node/request didn't match their ts.
    DATA=$(cat "$STATE" 2>/dev/null)

    # SEC-04: Read values and sanitise before echoing (strip chars outside safe set)
    REQ_TS=$(grep -o '"request_ts":[0-9]*' <<< "$DATA" | grep -o '[0-9]*')
    SIM_TS=$(grep -o '"sim_issues_ts":[0-9]*' <<< "$DATA" | grep -o '[0-9]*')
    GEN_TS=$(grep -o '"generate_ts":[0-9]*' <<< "$DATA" | grep -o '[0-9]*')
    NODE=$(grep -o '"selected_node":"[^"]*"' <<< "$DATA" | sed 's/.*":"//;s/"//' | tr -cd 'a-zA-Z0-9_-')
    REQUEST=$(grep -o '"request":"[^"]*"' <<< "$DATA" | sed 's/.*":"//;s/"//' | tr -cd 'a-zA-Z0-9 _-')

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
      echo "GENERATE_CHASSIS ts=$GEN_TS"
    fi

    SYNC_TS=$(grep -o '"sync_ts":[0-9]*' <<< "$DATA" | grep -o '[0-9]*')
    REIMPORT_TS=$(grep -o '"reimport_ts":[0-9]*' <<< "$DATA" | grep -o '[0-9]*')
    GDD_EXPORT_TS=$(grep -o '"gdd_export_ts":[0-9]*' <<< "$DATA" | grep -o '[0-9]*')
    SYNC_TS=${SYNC_TS:-0}
    REIMPORT_TS=${REIMPORT_TS:-0}
    GDD_EXPORT_TS=${GDD_EXPORT_TS:-0}

    if [ "$SYNC_TS" != "$LAST_SYNC_TS" ] && [ "$SYNC_TS" != "0" ]; then
      LAST_SYNC_TS=$SYNC_TS
      echo "SYNC_REQUESTED ts=$SYNC_TS"
    fi

    if [ "$REIMPORT_TS" != "$LAST_REIMPORT_TS" ] && [ "$REIMPORT_TS" != "0" ]; then
      LAST_REIMPORT_TS=$REIMPORT_TS
      echo "REIMPORT_REQUESTED ts=$REIMPORT_TS"
    fi

    if [ "$GDD_EXPORT_TS" != "$LAST_GDD_EXPORT_TS" ] && [ "$GDD_EXPORT_TS" != "0" ]; then
      LAST_GDD_EXPORT_TS=$GDD_EXPORT_TS
      echo "GDD_EXPORT_REQUESTED ts=$GDD_EXPORT_TS"
    fi
  fi

  sleep 0.5
done
