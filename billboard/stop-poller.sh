#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
EXAMPLE_CONFIG="$SCRIPT_DIR/config.env.example"

[ -f "$CONFIG_FILE" ] || cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
. "$CONFIG_FILE"

mkdir -p "$STATE_DIR" "$LOG_DIR"
touch "$STOP_FLAG"

is_pid_running() {
  pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

pid=""
[ -f "$PID_FILE" ] && pid="$(cat "$PID_FILE" 2>/dev/null || true)"

if is_pid_running "$pid"; then
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
