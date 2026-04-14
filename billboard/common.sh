#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
EXAMPLE_CONFIG="$SCRIPT_DIR/config.env.example"

[ -f "$CONFIG_FILE" ] || cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
. "$CONFIG_FILE"

STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
STOP_FLAG="${STOP_FLAG:-$STATE_DIR/stop.flag}"
PID_FILE="${PID_FILE:-$STATE_DIR/poller.pid}"
LOCK_DIR="${LOCK_DIR:-$STATE_DIR/poller.lock}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/poller.log}"
LAST_RESULT_FILE="${LAST_RESULT_FILE:-$STATE_DIR/last_result}"
LAST_SUCCESS_FILE="${LAST_SUCCESS_FILE:-$STATE_DIR/last_success}"

BILLBOARD_URL="${BILLBOARD_URL:-}"
PLAYLIST_URL="${PLAYLIST_URL:-}"
CHARGING_INTERVAL_SECONDS="${CHARGING_INTERVAL_SECONDS:-3600}"
BATTERY_INTERVAL_SECONDS="${BATTERY_INTERVAL_SECONDS:-43200}"
USE_SUSPEND="${USE_SUSPEND:-1}"
FETCH_TIMEOUT_SECONDS="${FETCH_TIMEOUT_SECONDS:-30}"
FETCH_RETRIES="${FETCH_RETRIES:-2}"
RENDER_ON_CHANGE="${RENDER_ON_CHANGE:-1}"
DAY_START_HOUR="${DAY_START_HOUR:-7}"
DAY_START_MINUTE="${DAY_START_MINUTE:-0}"
DAY_END_HOUR="${DAY_END_HOUR:-21}"
DAY_END_MINUTE="${DAY_END_MINUTE:-0}"
DAYLIGHT_URL="${DAYLIGHT_URL:-}"
DAYLIGHT_CACHE_FILE="${DAYLIGHT_CACHE_FILE:-$STATE_DIR/daylight.env}"

PLAYLIST_CACHE_DIR="${PLAYLIST_CACHE_DIR:-$STATE_DIR/playlist-cache}"
PLAYLIST_ENTRIES_FILE="${PLAYLIST_ENTRIES_FILE:-$STATE_DIR/playlist.entries}"
PLAYLIST_INDEX_FILE="${PLAYLIST_INDEX_FILE:-$STATE_DIR/playlist.index}"
PLAYLIST_COUNT_FILE="${PLAYLIST_COUNT_FILE:-$STATE_DIR/playlist.count}"
PLAYLIST_AUTOROTATE_FILE="${PLAYLIST_AUTOROTATE_FILE:-$STATE_DIR/playlist.autorotate}"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

ensure_runtime_dirs() {
  mkdir -p "$STATE_DIR" "$LOG_DIR" "$PLAYLIST_CACHE_DIR"
}

is_pid_running() {
  pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

is_poller_pid() {
  pid="${1:-}"
  [ -n "$pid" ] || return 1
  [ -r "/proc/$pid/cmdline" ] || return 1
  cmdline="$(tr '\000' ' ' </proc/"$pid"/cmdline 2>/dev/null || true)"
  case "$cmdline" in
    *"/billboard/poll-url.sh"*|*"poll-url.sh"*)
      return 0
      ;;
  esac
  return 1
}

fetch_url_to() {
  url="$1"
  destination="$2"

  if command -v curl >/dev/null 2>&1; then
    curl \
      -fsSL \
      --connect-timeout "$FETCH_TIMEOUT_SECONDS" \
      --max-time "$FETCH_TIMEOUT_SECONDS" \
      --retry "$FETCH_RETRIES" \
      --retry-delay 2 \
      "$url" \
      -o "$destination"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget \
      -q \
      -T "$FETCH_TIMEOUT_SECONDS" \
      -t "$FETCH_RETRIES" \
      -O "$destination" \
      "$url"
    return 0
  fi

  echo "no supported fetcher found (curl/wget)" >&2
  return 1
}

resolve_url() {
  base_url="$1"
  entry="$2"

  case "$entry" in
    http://*|https://*)
      printf '%s\n' "$entry"
      ;;
    *)
      base_dir="${base_url%/*}"
      printf '%s/%s\n' "$base_dir" "$entry"
      ;;
  esac
}

get_playlist_count() {
  if [ ! -f "$PLAYLIST_COUNT_FILE" ]; then
    echo 0
    return
  fi

  cat "$PLAYLIST_COUNT_FILE" 2>/dev/null || echo 0
}

get_playlist_index() {
  count="$(get_playlist_count)"
  if [ "$count" -le 0 ]; then
    echo 0
    return
  fi

  index=0
  if [ -f "$PLAYLIST_INDEX_FILE" ]; then
    index="$(cat "$PLAYLIST_INDEX_FILE" 2>/dev/null || echo 0)"
  fi

  case "$index" in
    ''|*[!0-9]*)
      index=0
      ;;
  esac

  if [ "$index" -ge "$count" ]; then
    index=0
  fi

  echo "$index"
}

set_playlist_index() {
  index="$1"
  printf '%s\n' "$index" >"$PLAYLIST_INDEX_FILE"
}

get_playlist_autorotate() {
  if [ -f "$PLAYLIST_AUTOROTATE_FILE" ]; then
    cat "$PLAYLIST_AUTOROTATE_FILE" 2>/dev/null || echo 1
    return
  fi

  echo 1
}

set_playlist_autorotate() {
  value="$1"
  printf '%s\n' "$value" >"$PLAYLIST_AUTOROTATE_FILE"
}

detect_power_profile() {
  if command -v lipc-get-prop >/dev/null 2>&1; then
    charging="$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null || true)"
    case "$(printf '%s' "$charging" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes)
        echo charging
        return
        ;;
    esac
  fi

  echo battery
}

current_interval_seconds() {
  profile="$(detect_power_profile)"
  if [ "$profile" = "charging" ]; then
    echo "$CHARGING_INTERVAL_SECONDS"
    return
  fi

  echo "$BATTERY_INTERVAL_SECONDS"
}

maybe_refresh_daylight_window() {
  [ -n "$DAYLIGHT_URL" ] || return 0

  ensure_runtime_dirs
  today="$(date '+%Y-%m-%d')"
  if [ -f "$DAYLIGHT_CACHE_FILE" ] && grep -q "^DATE=$today\$" "$DAYLIGHT_CACHE_FILE" 2>/dev/null; then
    return 0
  fi

  tmp_file="$DAYLIGHT_CACHE_FILE.tmp"
  if fetch_url_to "$DAYLIGHT_URL" "$tmp_file"; then
    mv -f "$tmp_file" "$DAYLIGHT_CACHE_FILE"
  else
    rm -f "$tmp_file"
  fi
}

load_daylight_window() {
  maybe_refresh_daylight_window

  window_start_hour="$DAY_START_HOUR"
  window_start_minute="$DAY_START_MINUTE"
  window_end_hour="$DAY_END_HOUR"
  window_end_minute="$DAY_END_MINUTE"

  if [ -f "$DAYLIGHT_CACHE_FILE" ]; then
    # Trusted file generated by the host helper.
    . "$DAYLIGHT_CACHE_FILE"
    window_start_hour="${DAY_START_HOUR:-$window_start_hour}"
    window_start_minute="${DAY_START_MINUTE:-$window_start_minute}"
    window_end_hour="${DAY_END_HOUR:-$window_end_hour}"
    window_end_minute="${DAY_END_MINUTE:-$window_end_minute}"
  fi
}

is_daytime_now() {
  load_daylight_window

  now_hour="$(date '+%H' | sed 's/^0*//')"
  now_minute="$(date '+%M' | sed 's/^0*//')"
  [ -n "$now_hour" ] || now_hour=0
  [ -n "$now_minute" ] || now_minute=0
  now_minutes=$((now_hour * 60 + now_minute))

  start_minutes=$((window_start_hour * 60 + window_start_minute))
  end_minutes=$((window_end_hour * 60 + window_end_minute))

  [ "$now_minutes" -ge "$start_minutes" ] && [ "$now_minutes" -lt "$end_minutes" ]
}

seconds_until_daytime() {
  load_daylight_window

  now_hour="$(date '+%H' | sed 's/^0*//')"
  now_minute="$(date '+%M' | sed 's/^0*//')"
  now_second="$(date '+%S' | sed 's/^0*//')"
  [ -n "$now_hour" ] || now_hour=0
  [ -n "$now_minute" ] || now_minute=0
  [ -n "$now_second" ] || now_second=0

  now_total=$((now_hour * 3600 + now_minute * 60 + now_second))
  start_total=$((window_start_hour * 3600 + window_start_minute * 60))
  end_total=$((window_end_hour * 3600 + window_end_minute * 60))

  if [ "$now_total" -lt "$start_total" ]; then
    echo $((start_total - now_total))
    return
  fi

  if [ "$now_total" -ge "$end_total" ]; then
    echo $(((24 * 3600 - now_total) + start_total))
    return
  fi

  echo 0
}

sleep_or_suspend() {
  seconds="$1"

  if [ "$USE_SUSPEND" = "1" ] && [ "$seconds" -ge 60 ]; then
    for path in /sys/class/rtc/rtc0/wakealarm /sys/class/rtc/rtc1/wakealarm /sys/class/rtc/rtc2/wakealarm; do
      if [ -w "$path" ]; then
        echo 0 >"$path" || true
        echo "+$seconds" >"$path"
        echo mem >/sys/power/state
        return 0
      fi
    done
  fi

  sleep "$seconds"
}
