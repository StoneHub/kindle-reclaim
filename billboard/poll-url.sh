#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

URL_OVERRIDE="${1:-}"

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    return 0
  fi

  old_pid=""
  [ -f "$PID_FILE" ] && old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_poller_pid "$old_pid"; then
    log "poller already running as pid $old_pid"
    exit 0
  fi

  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
}

cleanup() {
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1 || true
  rm -f "$PID_FILE"
  rm -rf "$LOCK_DIR"
}

[ -n "${BILLBOARD_URL:-$URL_OVERRIDE}" ] || [ -n "$PLAYLIST_URL" ] || {
  echo "usage: BILLBOARD_URL=<image-url> PLAYLIST_URL=<playlist-url> $0 [image-url]" >&2
  exit 2
}

if [ -n "$URL_OVERRIDE" ]; then
  BILLBOARD_URL="$URL_OVERRIDE"
fi

mkdir -p "$STATE_DIR" "$LOG_DIR"
acquire_lock
echo "$$" >"$PID_FILE"

trap cleanup EXIT INT TERM HUP
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true
log "poller started (current=${BILLBOARD_URL:-none} playlist=${PLAYLIST_URL:-none})"

while true; do
  if [ -f "$STOP_FLAG" ]; then
    log "stop flag found: $STOP_FLAG"
    exit 0
  fi

  if is_daytime_now; then
    if [ -n "$PLAYLIST_URL" ]; then
      if /bin/sh "$SCRIPT_DIR/sync-playlist.sh" && /bin/sh "$SCRIPT_DIR/render-active.sh"; then
        if [ "$(get_playlist_autorotate)" = "1" ]; then
          count="$(get_playlist_count)"
          if [ "$count" -gt 1 ]; then
            index="$(get_playlist_index)"
            set_playlist_index $(((index + 1) % count))
          fi
        fi
      else
        log "playlist sync/render failed for $PLAYLIST_URL"
      fi
    elif ! env CONFIG_FILE="$CONFIG_FILE" BILLBOARD_URL="$BILLBOARD_URL" /bin/sh "$SCRIPT_DIR/show-url.sh"; then
      log "fetch/render failed for $BILLBOARD_URL"
    fi
  else
    sleep_seconds="$(seconds_until_daytime)"
    log "night window active; sleeping ${sleep_seconds}s until daytime"
    sleep_or_suspend "$sleep_seconds"
    continue
  fi

  profile="$(detect_power_profile)"
  interval_seconds="$(current_interval_seconds)"
  log "sleeping ${interval_seconds}s (power=${profile})"
  sleep_or_suspend "$interval_seconds"
done
