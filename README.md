# Kindle Reclaim

Turn an old jailbroken Kindle into a low-power Wi-Fi billboard.

This repo contains:

- Kindle-side billboard runtime scripts in [billboard](billboard)
- a KUAL launcher in [kual/kindle-billboard](kual/kindle-billboard)
- an agent skill and host-side publisher in [skills/kindle-billboard](skills/kindle-billboard)
- a repeatable deploy helper in [tools/deploy-kindle-billboard.ps1](tools/deploy-kindle-billboard.ps1)

## What It Does

The Kindle acts as a pull-based e-ink client:

1. a host publishes `current.png`
2. the Kindle poller fetches it over Wi-Fi
3. the Kindle renders it with `fbink` or `eips`
4. the device sleeps between refreshes to preserve battery

The host can publish:

- local images
- image URLs
- generated text cards
- Tavily-backed current-news meme plans for an external agent

PDFs are expected to be rasterized on the host first.

## Verified Hardware

Verified on:

- Kindle `(7th Generation)` / `KT2, BASIC`
- firmware `5.12.2.2`
- codename `Bourbon/Wario`

Verified behavior:

- Wi-Fi fetch from host over LAN HTTP
- full-screen render on the Kindle
- host-side publish pipeline for agent-driven updates

More detailed device notes live in [skills/kindle-billboard/references/current-setup.md](skills/kindle-billboard/references/current-setup.md).
Session handoff notes for the next agent live in [skills/kindle-billboard/references/next-agent-handoff.md](skills/kindle-billboard/references/next-agent-handoff.md).

## Repo Layout

- [billboard](billboard): on-device runtime
- [kual/kindle-billboard](kual/kindle-billboard): KUAL extension
- [skills/kindle-billboard](skills/kindle-billboard): agent skill, host publisher, MCP contract notes
- [tools](tools): deployment helpers

## Host Workflow

Publish a text card:

```powershell
python .\skills\kindle-billboard\scripts\publish_kindle_billboard.py publish-text --title "Barn Notes" --body "Fence crew on south pasture at 18:00."
```

Publish an image:

```powershell
python .\skills\kindle-billboard\scripts\publish_kindle_billboard.py publish-file .\path\to\image.png
```

Serve the publish directory:

```powershell
python .\skills\kindle-billboard\scripts\publish_kindle_billboard.py serve
```

Check status:

```powershell
python .\skills\kindle-billboard\scripts\publish_kindle_billboard.py status
```

Prepare a daily current-news meme brief:

```powershell
python .\skills\kindle-billboard\scripts\plan_daily_news_meme.py
```

The planner expects `TAVILY_API_KEY` in the host environment.

Publish a news meme card after your agent has made the image and caption:

```powershell
python .\skills\kindle-billboard\scripts\publish_kindle_billboard.py publish-news-meme --headline "..." --joke "..." --summary "..." --source-name "Reuters" --source-url "https://..." --image C:\path\to\news-meme.png --footer "OpenClaw daily cron"
```

## Kindle Workflow

Deploy to the Kindle:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy-kindle-billboard.ps1 -StartPoller
```

On the Kindle, use KUAL:

- `Start Poller`
- `Render Current Once`
- `Restart Poller`
- `Stop Poller`

Or run directly:

```sh
/mnt/us/billboard/start-poller.sh
/mnt/us/billboard/status.sh
/mnt/us/billboard/stop-poller.sh
```

Current deploy helper behavior:

- detects the active LAN IP if `-BillboardUrl` is not supplied
- rewrites `/mnt/us/billboard/config.env`
- can start the poller immediately with `-StartPoller`
- keeps render-only-on-change enabled by default to avoid needless refreshes

## Current Design Choices

- Stay on Amazon OS; do not replace the OS
- Prefer Wi-Fi pull over browser kiosk behavior
- Use grayscale `600x800` raster images as the device contract
- Use plain HTTP on trusted LAN by default because old Kindle TLS is weak
- For current-news humor, use Tavily to select the story, then have an external agent create an original meme image or joke card

## Daily News Meme Workflow

Recommended flow for OpenClaw or another cron-driven agent:

1. `plan_daily_news_meme.py` calls Tavily Search with `topic=news`, `time_range=day`, `search_depth=basic`, and a small trusted domain allowlist.
2. Your agent reads the generated JSON plan, writes one short joke, and creates one original high-contrast image for `600x800` grayscale.
3. The agent publishes the result with `publish-news-meme`.
4. The Kindle poller fetches the updated `current.png` over Wi-Fi.

The detailed rationale and source links live in [skills/kindle-billboard/references/daily-news-meme-workflow.md](skills/kindle-billboard/references/daily-news-meme-workflow.md).

Practical cron shape on your ARM host:

1. cron runs `plan_daily_news_meme.py`
2. OpenClaw picks up the resulting JSON
3. OpenClaw generates `news-meme.png`
4. OpenClaw runs `publish-news-meme`

Safest content path:

- generate original satirical art or a text-first joke card
- avoid depending on scraped social-media memes or article-page screenshots
- keep on-image text sparse so it survives Kindle grayscale conversion

## Done

The project is considered working when:

1. the host updates `current.png`
2. the Kindle fetches `GET /current.png` over Wi-Fi
3. the new image appears on-screen
4. the poll loop can be started and stopped safely
5. a daily-news plan can be generated from Tavily and handed to an external agent without manual lookup

## Not In This Repo

Ignored on purpose:

- jailbreak payloads and installer binaries
- vendored upstream repos used for reference
- runtime logs and generated publish artifacts
