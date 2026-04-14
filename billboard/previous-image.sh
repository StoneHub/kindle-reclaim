#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

ensure_runtime_dirs
/bin/sh "$SCRIPT_DIR/sync-playlist.sh" >/dev/null 2>&1 || true
count="$(get_playlist_count)"
[ "$count" -gt 0 ] || exit 0

index="$(get_playlist_index)"
previous_index=$((index - 1))
if [ "$previous_index" -lt 0 ]; then
  previous_index=$((count - 1))
fi
set_playlist_index "$previous_index"
exec /bin/sh "$SCRIPT_DIR/render-active.sh"
