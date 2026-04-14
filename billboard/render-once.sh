#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

if [ -n "$PLAYLIST_URL" ]; then
  /bin/sh "$SCRIPT_DIR/sync-playlist.sh" >/dev/null 2>&1 || true
  exec /bin/sh "$SCRIPT_DIR/render-active.sh"
fi

# Manual render should always redraw the current image, even when the fetched
# file bytes match the cached copy from the poll loop.
exec env CONFIG_FILE="$CONFIG_FILE" BILLBOARD_URL="${BILLBOARD_URL:-}" RENDER_ON_CHANGE=0 /bin/sh "$SCRIPT_DIR/show-url.sh"
