#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

ensure_runtime_dirs
count="$(get_playlist_count)"

if [ "$count" -le 0 ] || [ ! -f "$PLAYLIST_ENTRIES_FILE" ]; then
  exec env CONFIG_FILE="$CONFIG_FILE" RENDER_ON_CHANGE=0 /bin/sh "$SCRIPT_DIR/show-url.sh" "${BILLBOARD_URL:-}"
fi

index="$(get_playlist_index)"
line_number=$((index + 1))
entry="$(sed -n "${line_number}p" "$PLAYLIST_ENTRIES_FILE" 2>/dev/null || true)"
[ -n "$entry" ] || exec env CONFIG_FILE="$CONFIG_FILE" RENDER_ON_CHANGE=0 /bin/sh "$SCRIPT_DIR/show-url.sh" "${BILLBOARD_URL:-}"

image_path="${entry%%|*}"
[ -f "$image_path" ] || exec env CONFIG_FILE="$CONFIG_FILE" RENDER_ON_CHANGE=0 /bin/sh "$SCRIPT_DIR/show-url.sh" "${BILLBOARD_URL:-}"

exec env CONFIG_FILE="$CONFIG_FILE" /bin/sh "$SCRIPT_DIR/show-file.sh" "$image_path"
