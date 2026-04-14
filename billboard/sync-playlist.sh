#!/bin/sh
set -eu

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/common.sh"

[ -n "$PLAYLIST_URL" ] || exit 0

ensure_runtime_dirs

manifest_tmp="$STATE_DIR/playlist.txt.tmp"
manifest_file="$STATE_DIR/playlist.txt"
entries_tmp="$PLAYLIST_ENTRIES_FILE.tmp"

fetch_url_to "$PLAYLIST_URL" "$manifest_tmp"
mv -f "$manifest_tmp" "$manifest_file"

: >"$entries_tmp"
count=0
while IFS= read -r entry || [ -n "$entry" ]; do
  case "$entry" in
    ''|\#*)
      continue
      ;;
  esac

  count=$((count + 1))
  url="$(resolve_url "$PLAYLIST_URL" "$entry")"
  image_path="$PLAYLIST_CACHE_DIR/$(printf '%03d' "$count").img"
  tmp_path="$image_path.tmp"
  fetch_url_to "$url" "$tmp_path"
  mv -f "$tmp_path" "$image_path"
  printf '%s|%s\n' "$image_path" "$url" >>"$entries_tmp"
done <"$manifest_file"

mv -f "$entries_tmp" "$PLAYLIST_ENTRIES_FILE"
printf '%s\n' "$count" >"$PLAYLIST_COUNT_FILE"

current_index="$(get_playlist_index)"
if [ "$count" -le 0 ]; then
  set_playlist_index 0
elif [ "$current_index" -ge "$count" ]; then
  set_playlist_index 0
fi
