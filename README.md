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
4. the device refreshes on its poll interval; suspend between polls is optional

The host can publish:

- local images
- image URLs
- generated text cards
- Tavily-backed current-news meme plans for an external agent

When SSH is reachable, the host can also push the already-published `current.png` to the Kindle and render it immediately without waiting for the Wi-Fi poll loop.

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
- `Render Current Once` from KUAL rendered the current card on-device
- `Start Poller` from KUAL resumed the Wi-Fi pull loop and advanced the screen to a newly published card

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

Keep this process running whenever you expect the Kindle poller to update untethered over Wi-Fi. If direct SSH push works but host-side `GET /current.png` does not appear, check that `0.0.0.0:8765` is still listening before changing Kindle-side code.

Or use the background helper that manages the host HTTP loop and logs:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\kindle-host-serve.ps1 -Action ensure
```

Install the Windows-login Startup entry for that helper:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-kindle-host-startup.ps1
```

Check status:

```powershell
python .\skills\kindle-billboard\scripts\publish_kindle_billboard.py status
```

Push the current published image directly to the Kindle over SSH and render it immediately:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\push-current-kindle.ps1
```

On this Windows host, the Wi-Fi path in `push-current-kindle.ps1` now prefers native `ssh.exe` and `scp.exe` instead of WSL. That was the reliable path when WSL could not route to the Kindle over LAN.

Install this host's SSH public key into mounted Kindle USB storage so later Wi-Fi or USBNetwork SSH sessions can use key auth:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-kindle-ssh-key.ps1
```

After the host key is installed and the Kindle is ejected back out of drive mode, set the root password to `kindle` over SSH:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\set-kindle-root-password.ps1 -NewPassword kindle
```

This helper now verifies the change with a real password SSH login after updating the password.

Install the Kindle boot-time poller hook over Wi-Fi SSH:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-kindle-autostart.ps1
```

For USBNetwork push on Windows, the Kindle bus must already be shared with `usbipd` first. If `auto` mode reports no reachable SSH transport and `usbipd` shows the Kindle as `Not shared`, run `usbipd bind --busid <busid>` as administrator before retrying the USB path.

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
- defaults to a wall-power profile: `INTERVAL_SECONDS=60`, `USE_SUSPEND=0`

If you use plain USB mass storage instead of USBNetwork for maintenance:

- compare `/mnt/us/billboard` and `/mnt/us/extensions/kindle-billboard` against the repo before debugging Wi-Fi
- do not expect the Wi-Fi poll loop to fetch while the Kindle is mounted as a USB drive; eject first, then watch for new host-side `GET /current.png`
- copy shell and env files byte-for-byte from the repo; do not rewrite `.sh` or `config.env` from Windows text tools that may introduce CRLF line endings
- `Render Current Once` is the fastest smoke test before blaming the poll loop
- the KUAL footer status text is not proof that the poller actually started; trust logs, PID/lock state, host `GET` traffic, and the screen
- on this device, if the poller is already running, a power-button sleep/wake cycle can effectively trigger a near-immediate refresh
- after the text path works, publish a real image or meme before declaring the billboard pipeline healthy

Host-driven push has a hard transport limit:

- plain USB mass-storage mode cannot update the live screen by itself because the Kindle is exposing storage, not running host-triggered render commands
- a true host-side push requires SSH reachability over USBNetwork or Wi-Fi SSH
- if Wi-Fi SSH is listening but current credentials are unknown, mounted USB storage can repair host access by writing the host public key to `/mnt/us/usbnet/etc/authorized_keys`
- `tools/install-kindle-ssh-key.ps1`, `tools/set-kindle-root-password.ps1`, and `tools/push-current-kindle.ps1` are the repo paths for that immediate render flow
- the SSH helpers now prefer `~/.ssh/id_ed25519` when it exists and otherwise fall back to `KINDLE_SSH_PASSWORD` or an explicit `-SshPassword`
- on this Windows host, native `ssh.exe` and `scp.exe` are the preferred Wi-Fi path; WSL can still be useful for USB transport but may fail LAN routing
- on this Kindle, the usbnet `auto` trigger file was already enabled. The reliable appliance profile is `USE_WIFI="true"` plus `USE_WIFI_SSHD_ONLY="true"` so boot-time SSH does not steal normal USB mass-storage maintenance
- if Windows can see the Kindle as a USB device but there is no drive letter and `push-current-kindle.ps1` reports no reachable SSH transport, the blocker is transport state, not billboard render logic

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

Current verified status on `2026-04-12`:

1. `Render Current Once` works from KUAL
2. `Start Poller` from KUAL works
3. the host saw fresh `GET /current.png` requests after the fixes
4. the Kindle advanced from `Poller Afterparty Check` to `Wi-Fi Victory Lap` over Wi-Fi
5. Wi-Fi SSH key auth and password auth both work from native Windows OpenSSH
6. `tools\push-current-kindle.ps1` rendered a real weather/news image immediately over Wi-Fi SSH
7. after publishing that image at `21:13:07` local time, the host logged a fresh Kindle `GET /current.png` at `21:13:58`
8. `tools\install-kindle-autostart.ps1` installed a Kindle upstart job that survived a real reboot and restarted the poller automatically
9. the host `serve` loop is managed by `tools\kindle-host-serve.ps1`, and a Windows Startup entry now reruns that helper at login

Still not done:

- wall-power appliance behavior is tuned for a live power cord and reboot-tested on the Kindle side
- the host `serve` loop now has a Windows-login Startup entry, but it is not a machine-wide service; if the host boots to a logged-out state, untethered polling still waits for login or a manual helper run

## Lessons From 2026-04-12

- The first failure was deployed-file drift, not broken Wi-Fi.
- The next failure was stale `state/poller.pid` and `state/poller.lock`, which made `Start Poller` look dead.
- The loudest shell break came from Windows CRLF in `/mnt/us/billboard/config.env`; Kindle shell and sourced env files need LF.
- KUAL helper execution became reliable only after using absolute `/mnt/us/...` paths and routing helper-to-helper calls through `/bin/sh`.
- The footer toast in KUAL is not authoritative evidence. Done requires fresh publish, fresh host `GET /current.png`, and a changed screen.
- Text cards are good smoke tests, but final validation should include a real image publish.
- Host-driven push is possible only when SSH is reachable; mounted USB storage by itself is not a live render transport.
- Native Windows OpenSSH was the reliable Wi-Fi path for this host. WSL routing failed even while Windows could reach `192.168.50.162`.
- A dead host `serve` process on port `8765` can look like a Kindle or poller bug. Confirm host listening state before touching Kindle-side scripts.
- On this firmware, the custom Kindle boot hook worked when attached to upstart `started framework`. The first attempt using `framework_ready` did not survive a real reboot.
- A manual `Render Current Once` action must force a redraw. If it honors `RENDER_ON_CHANGE=1`, it can exit as `unchanged` and look broken from KUAL even when the action actually executed.
- KindleTool `info` shows this device's serial-derived default root password path is `pre-Wario`, but the live device no longer accepts the untouched default password. Treat that as an auth-state issue, not a billboard bug.
- The mounted usbnet package already had `/mnt/us/usbnet/auto` enabled. That explained the user's "won't go back to USB mode" complaint. The fix was to keep Wi-Fi SSH but switch usbnet into SSHD-only mode so maintenance USB storage still works.

## Not In This Repo

Ignored on purpose:

- jailbreak payloads and installer binaries
- vendored upstream repos used for reference
- runtime logs and generated publish artifacts
