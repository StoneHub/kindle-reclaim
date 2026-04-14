# MCP Tool Contract

If you wrap this workflow in an MCP server, keep the tool surface small.

## Recommended tools

### `kindle_billboard_status`

Inputs:

- `host_ip` optional
- `port` optional, default `8765`

Output:

- `publish_dir`
- `current_exists`
- `current_path`
- `metadata_path`
- `guessed_current_url`
- `guessed_playlist_url`
- `guessed_daylight_url`
- `notes`

Maps to:

```bash
python scripts/publish_kindle_billboard.py status
```

### `kindle_billboard_publish_file`

Inputs:

- `source` required; local path or `http(s)` URL to an image
- `note` optional

Output:

- path to `current.png`
- metadata JSON

Maps to:

```bash
python scripts/publish_kindle_billboard.py publish-file <source>
```

### `kindle_billboard_publish_playlist`

Inputs:

- `sources` required; one or more local paths or `http(s)` URLs to images
- `note` optional

Output:

- path to `playlist.txt`
- `current.png` updated to the first slide
- playlist metadata JSON

Maps to:

```bash
python scripts/publish_kindle_billboard.py publish-playlist <source> <source> ...
```

### `kindle_billboard_refresh_daylight`

Inputs:

- `day_start_hour` optional fallback, default `7`
- `day_end_hour` optional fallback, default `21`

Output:

- path to `daylight.env`

Maps to:

```bash
python scripts/publish_kindle_billboard.py refresh-daylight
```

### `kindle_billboard_publish_text`

Inputs:

- `title` required
- `body` required
- `footer` optional

Output:

- path to `current.png`
- metadata JSON

Maps to:

```bash
python scripts/publish_kindle_billboard.py publish-text --title ... --body ... --footer ...
```

### `kindle_billboard_serve`

Inputs:

- `host` optional, default `0.0.0.0`
- `port` optional, default `8765`

Behavior:

- starts a static HTTP server rooted at the publish directory

Maps to:

```bash
python scripts/publish_kindle_billboard.py serve
```

## Keep out of the first MCP version

- direct Wi-Fi SSH control of the Kindle
- on-device PDF rendering
- stateful UI/browser automation on the Kindle
- complicated queueing or multi-device routing
