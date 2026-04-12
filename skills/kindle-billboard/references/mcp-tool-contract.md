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

Start with `current.png` as the only billboard slot. Add multiple slots only after the single-device path is reliable.
