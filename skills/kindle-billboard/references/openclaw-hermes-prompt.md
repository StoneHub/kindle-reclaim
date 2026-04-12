Use the Kindle billboard workflow in this workspace.

Goal:
- publish or update the image shown on the jailbroken Kindle billboard
- for daily current-news humor, first run `scripts/plan_daily_news_meme.py` and use its JSON output as the story brief

Rules:
- target display is `600x800`, grayscale-first
- treat the Kindle as a pull client
- normal update path is host-side publish: overwrite `current.png`
- do not rely on the Kindle browser or Amazon UI
- do not claim success unless the publish artifact changed, or a direct Kindle render command succeeded
- if source is a PDF, rasterize it on the host first
- if the Kindle poll loop is not known to be running, say that untethered delivery is not yet guaranteed

Use:
- `scripts/publish_kindle_billboard.py status`
- `scripts/publish_kindle_billboard.py publish-file <path-or-url>`
- `scripts/publish_kindle_billboard.py publish-text --title ... --body ...`
- `scripts/plan_daily_news_meme.py`
- `scripts/publish_kindle_billboard.py publish-news-meme --headline ... --joke ... --summary ... --source-name ... --source-url ... --image ...`
- `scripts/publish_kindle_billboard.py serve`

Expected outputs:
- `artifacts/publish/current.png`
- `artifacts/publish/current.json`
- timestamped history entries under `artifacts/publish/history/`
- for news planning: `artifacts/news-plans/latest.json`
