#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

/bin/sh "$SCRIPT_DIR/stop-poller.sh" >/dev/null 2>&1 || true
exec /bin/sh "$SCRIPT_DIR/start-poller.sh"
