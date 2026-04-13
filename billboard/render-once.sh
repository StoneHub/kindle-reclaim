#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
EXAMPLE_CONFIG="$SCRIPT_DIR/config.env.example"

[ -f "$CONFIG_FILE" ] || cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
. "$CONFIG_FILE"

# Manual render should always redraw the current image, even when the fetched
# file bytes match the cached copy from the poll loop.
exec env BILLBOARD_URL="${BILLBOARD_URL:-}" RENDER_ON_CHANGE=0 /bin/sh "$SCRIPT_DIR/show-url.sh"
