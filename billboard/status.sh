#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

pid=""
[ -f "$PID_FILE" ] && pid="$(cat "$PID_FILE" 2>/dev/null || true)"

if is_poller_pid "$pid"; then
  state="running"
elif [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  state="stale-pid"
else
  state="stopped"
fi

echo "state=$state"
echo "pid=${pid:-}"
echo "url=${BILLBOARD_URL:-}"
echo "playlist_url=${PLAYLIST_URL:-}"
echo "charging_interval=${CHARGING_INTERVAL_SECONDS:-}"
echo "battery_interval=${BATTERY_INTERVAL_SECONDS:-}"
echo "power_profile=$(detect_power_profile)"
echo "day_window=${DAY_START_HOUR:-}:${DAY_START_MINUTE:-}-${DAY_END_HOUR:-}:${DAY_END_MINUTE:-}"
echo "daylight_url=${DAYLIGHT_URL:-}"
echo "playlist_count=$(get_playlist_count)"
echo "playlist_index=$(get_playlist_index)"
echo "playlist_autorotate=$(get_playlist_autorotate)"
echo "suspend=${USE_SUSPEND:-}"
echo "log=${LOG_FILE:-}"
if [ -f "${LAST_RESULT_FILE:-}" ]; then
  echo "last_result=$(cat "$LAST_RESULT_FILE" 2>/dev/null || true)"
fi
if [ -f "${LAST_SUCCESS_FILE:-}" ]; then
  echo "last_success=$(cat "$LAST_SUCCESS_FILE" 2>/dev/null || true)"
fi
