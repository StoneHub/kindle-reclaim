#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
EXAMPLE_CONFIG="$SCRIPT_DIR/config.env.example"

[ -f "$CONFIG_FILE" ] || cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
. "$CONFIG_FILE"

exec env BILLBOARD_URL="${BILLBOARD_URL:-}" "$SCRIPT_DIR/show-url.sh"
