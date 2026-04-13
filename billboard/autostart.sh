#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
LOG_FILE="$LOG_DIR/autostart.log"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"

mkdir -p "$LOG_DIR"

{
  echo "$(date '+%Y-%m-%d %H:%M:%S') autostart invoked"

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') config missing: $CONFIG_FILE"
    exit 0
  fi

  # Give framework/userstore a moment to settle before launching the poller.
  sleep 8

  /bin/sh "$SCRIPT_DIR/start-poller.sh"
} >>"$LOG_FILE" 2>&1
