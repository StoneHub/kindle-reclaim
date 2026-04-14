#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

ensure_runtime_dirs
touch "$STOP_FLAG"

pid=""
[ -f "$PID_FILE" ] && pid="$(cat "$PID_FILE" 2>/dev/null || true)"

if is_poller_pid "$pid"; then
  kill "$pid" 2>/dev/null || true
  i=0
  while [ "$i" -lt 10 ] && is_pid_running "$pid"; do
    sleep 1
    i=$((i + 1))
  done
  if is_pid_running "$pid"; then
    kill -9 "$pid" 2>/dev/null || true
  fi
fi

rm -f "$PID_FILE"
rm -rf "$LOCK_DIR"
rm -f "$STOP_FLAG"

echo "stopped"
