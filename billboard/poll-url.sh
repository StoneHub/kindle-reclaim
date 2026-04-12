#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

URL="${BILLBOARD_URL:-${1:-}}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-900}"
USE_SUSPEND="${USE_SUSPEND:-1}"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
STOP_FLAG="${STOP_FLAG:-$STATE_DIR/stop.flag}"
PID_FILE="${PID_FILE:-$STATE_DIR/poller.pid}"
LOCK_DIR="${LOCK_DIR:-$STATE_DIR/poller.lock}"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

is_pid_running() {
  pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    return 0
  fi

  old_pid=""
  [ -f "$PID_FILE" ] && old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_pid_running "$old_pid"; then
    log "poller already running as pid $old_pid"
    exit 0
  fi

  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
}

find_wakealarm() {
  for path in \
    /sys/class/rtc/rtc0/wakealarm \
    /sys/class/rtc/rtc1/wakealarm \
    /sys/class/rtc/rtc2/wakealarm
  do
    if [ -w "$path" ]; then
      echo "$path"
      return 0
    fi
  done

  return 1
}

sleep_or_suspend() {
  seconds="$1"

  if [ "$USE_SUSPEND" = "1" ] && [ "$seconds" -ge 60 ]; then
    WAKEALARM_PATH="$(find_wakealarm || true)"
    if [ -n "${WAKEALARM_PATH:-}" ]; then
      echo 0 >"$WAKEALARM_PATH" || true
      echo "+$seconds" >"$WAKEALARM_PATH"
      echo mem >/sys/power/state
      return 0
    fi
  fi

  sleep "$seconds"
}

cleanup() {
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1 || true
  rm -f "$PID_FILE"
  rm -rf "$LOCK_DIR"
}

[ -n "$URL" ] || {
  echo "usage: BILLBOARD_URL=<image-url> $0 [image-url]" >&2
  exit 2
}

mkdir -p "$STATE_DIR" "$LOG_DIR"
acquire_lock
echo "$$" >"$PID_FILE"

trap cleanup EXIT INT TERM HUP
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true
log "poller started for $URL (interval=${INTERVAL_SECONDS}s suspend=${USE_SUSPEND})"

while true; do
  if [ -f "$STOP_FLAG" ]; then
    log "stop flag found: $STOP_FLAG"
    exit 0
  fi

  if ! BILLBOARD_URL="$URL" "$SCRIPT_DIR/show-url.sh"; then
    log "fetch/render failed for $URL"
  fi

  sleep_or_suspend "$INTERVAL_SECONDS"
done
