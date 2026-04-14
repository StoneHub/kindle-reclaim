#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

ensure_runtime_dirs
current="$(get_playlist_autorotate)"
if [ "$current" = "1" ]; then
  set_playlist_autorotate 0
  echo "autorotate=off"
  exit 0
fi

set_playlist_autorotate 1
echo "autorotate=on"
