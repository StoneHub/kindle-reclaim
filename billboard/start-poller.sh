#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

ensure_runtime_dirs
rm -f "$STOP_FLAG"

if [ -f "$PID_FILE" ]; then
  existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_poller_pid "$existing_pid"; then
    echo "already running: $existing_pid"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

if [ -f "$LOG_FILE" ]; then
  log_size="$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)"
  if [ "$log_size" -gt 262144 ]; then
    mv "$LOG_FILE" "$LOG_FILE.1"
  fi
fi

nohup env CONFIG_FILE="$CONFIG_FILE" /bin/sh "$SCRIPT_DIR/poll-url.sh" >>"$LOG_FILE" 2>&1 &
sleep 1

new_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if is_pid_running "$new_pid"; then
  echo "started: $new_pid"
  exit 0
fi

echo "failed to start poller" >&2
tail -n 20 "$LOG_FILE" 2>/dev/null || true
exit 1
