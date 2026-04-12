#!/bin/sh
set -eu

URL="${1:-${BILLBOARD_URL:-}}"
TMP_DIR="${TMPDIR:-/tmp}/kindle-billboard"
OUT_FILE="$TMP_DIR/current.img"

usage() {
  echo "usage: $0 <image-url>" >&2
  exit 2
}

fetch_image() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$OUT_FILE"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$OUT_FILE" "$URL"
    return
  fi

  echo "no supported fetcher found (curl/wget)" >&2
  exit 4
}

render_image() {
  if command -v fbink >/dev/null 2>&1; then
    fbink -q -f -g "file=$OUT_FILE,w=-1,h=-1,dither"
    return
  fi

  if [ -x /usr/sbin/eips ]; then
    /usr/sbin/eips -f -g "$OUT_FILE"
    return
  fi

  echo "no supported renderer found (fbink/eips)" >&2
  exit 5
}

[ -n "$URL" ] || usage

case "$URL" in
  *.pdf|*.PDF)
    echo "PDF input is not rendered on-device; convert to PNG/JPEG server-side first." >&2
    exit 3
    ;;
esac

mkdir -p "$TMP_DIR"
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true
fetch_image
render_image
