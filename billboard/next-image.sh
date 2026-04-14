#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

ensure_runtime_dirs
/bin/sh "$SCRIPT_DIR/sync-playlist.sh" >/dev/null 2>&1 || true
count="$(get_playlist_count)"
[ "$count" -gt 0 ] || exit 0

index="$(get_playlist_index)"
next_index=$(((index + 1) % count))
set_playlist_index "$next_index"
exec /bin/sh "$SCRIPT_DIR/render-active.sh"
