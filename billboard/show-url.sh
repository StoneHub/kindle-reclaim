#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

URL="${1:-${BILLBOARD_URL:-}}"
TMP_DIR="${TMPDIR:-/tmp}/kindle-billboard"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
FETCH_TIMEOUT_SECONDS="${FETCH_TIMEOUT_SECONDS:-30}"
FETCH_RETRIES="${FETCH_RETRIES:-2}"
RENDER_ON_CHANGE="${RENDER_ON_CHANGE:-1}"
LAST_RESULT_FILE="${LAST_RESULT_FILE:-$STATE_DIR/last_result}"
LAST_SUCCESS_FILE="${LAST_SUCCESS_FILE:-$STATE_DIR/last_success}"
NEW_FILE="$TMP_DIR/current.new"
CACHE_FILE="$TMP_DIR/current.img"

usage() {
  echo "usage: $0 <image-url>" >&2
  exit 2
}

record_result() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" >"$LAST_RESULT_FILE"
}

record_success() {
  mkdir -p "$STATE_DIR"
  date '+%Y-%m-%d %H:%M:%S' >"$LAST_SUCCESS_FILE"
}

fetch_image() {
  if command -v curl >/dev/null 2>&1; then
    curl \
      -fsSL \
      --connect-timeout "$FETCH_TIMEOUT_SECONDS" \
      --max-time "$FETCH_TIMEOUT_SECONDS" \
      --retry "$FETCH_RETRIES" \
      --retry-delay 2 \
      "$URL" \
      -o "$NEW_FILE"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget \
      -q \
      -T "$FETCH_TIMEOUT_SECONDS" \
      -t "$FETCH_RETRIES" \
      -O "$NEW_FILE" \
      "$URL"
    return
  fi

  echo "no supported fetcher found (curl/wget)" >&2
  exit 4
}

render_image() {
  if command -v fbink >/dev/null 2>&1; then
    fbink -q -f -g "file=$CACHE_FILE,w=-1,h=-1,dither"
    return
  fi

  if [ -x /usr/sbin/eips ]; then
    /usr/sbin/eips -f -g "$CACHE_FILE"
    return
  fi

  echo "no supported renderer found (fbink/eips)" >&2
  exit 5
}

files_match() {
  left="$1"
  right="$2"

  if [ ! -f "$left" ] || [ ! -f "$right" ]; then
    return 1
  fi

  if command -v cmp >/dev/null 2>&1; then
    cmp -s "$left" "$right"
    return
  fi

  if command -v cksum >/dev/null 2>&1; then
    [ "$(cksum <"$left")" = "$(cksum <"$right")" ]
    return
  fi

  return 1
}

[ -n "$URL" ] || usage

case "$URL" in
  *.pdf|*.PDF)
    echo "PDF input is not rendered on-device; convert to PNG/JPEG server-side first." >&2
    exit 3
    ;;
esac

mkdir -p "$TMP_DIR" "$STATE_DIR"
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true
rm -f "$NEW_FILE"
fetch_image

if [ "$RENDER_ON_CHANGE" = "1" ] && files_match "$NEW_FILE" "$CACHE_FILE"; then
  rm -f "$NEW_FILE"
  record_result "unchanged"
  exit 0
fi

mv -f "$NEW_FILE" "$CACHE_FILE"
render_image
record_result "rendered"
record_success
