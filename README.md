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

## Kindle Workflow

Deploy to the Kindle:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy-kindle-billboard.ps1
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

## Current Design Choices

- Stay on Amazon OS; do not replace the OS
- Prefer Wi-Fi pull over browser kiosk behavior
- Use grayscale `600x800` raster images as the device contract
- Use plain HTTP on trusted LAN by default because old Kindle TLS is weak

## Done

The project is considered working when:

1. the host updates `current.png`
2. the Kindle fetches `GET /current.png` over Wi-Fi
3. the new image appears on-screen
4. the poll loop can be started and stopped safely

## Not In This Repo

Ignored on purpose:

- jailbreak payloads and installer binaries
- vendored upstream repos used for reference
- runtime logs and generated publish artifacts
