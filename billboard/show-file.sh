#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

IMAGE_PATH="${1:-}"
TMP_DIR="${TMPDIR:-/tmp}/kindle-billboard"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
LAST_RESULT_FILE="${LAST_RESULT_FILE:-$STATE_DIR/last_result}"
LAST_SUCCESS_FILE="${LAST_SUCCESS_FILE:-$STATE_DIR/last_success}"
CACHE_FILE="$TMP_DIR/current.img"

usage() {
  echo "usage: $0 <image-path>" >&2
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

render_image() {
  image_file="$1"

  if command -v fbink >/dev/null 2>&1; then
    fbink -q -f -g "file=$image_file,w=-1,h=-1,dither"
    return
  fi

  if [ -x /usr/sbin/eips ]; then
    /usr/sbin/eips -f -g "$image_file"
    return
  fi

  echo "no supported renderer found (fbink/eips)" >&2
  exit 5
}

[ -n "$IMAGE_PATH" ] || usage
[ -f "$IMAGE_PATH" ] || {
  echo "image file not found: $IMAGE_PATH" >&2
  exit 3
}

case "$IMAGE_PATH" in
  *.pdf|*.PDF)
    echo "PDF input is not rendered on-device; convert to PNG/JPEG server-side first." >&2
    exit 4
    ;;
esac

mkdir -p "$TMP_DIR" "$STATE_DIR"
cp "$IMAGE_PATH" "$CACHE_FILE"
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true
render_image "$CACHE_FILE"
record_result "rendered_local"
record_success
