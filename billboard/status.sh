#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
EXAMPLE_CONFIG="$SCRIPT_DIR/config.env.example"

[ -f "$CONFIG_FILE" ] || cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
. "$CONFIG_FILE"

pid=""
[ -f "$PID_FILE" ] && pid="$(cat "$PID_FILE" 2>/dev/null || true)"

if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  state="running"
else
  state="stopped"
fi

echo "state=$state"
echo "pid=${pid:-}"
echo "url=${BILLBOARD_URL:-}"
echo "interval=${INTERVAL_SECONDS:-}"
echo "suspend=${USE_SUSPEND:-}"
echo "log=${LOG_FILE:-}"
