---
name: kindle-billboard
description: "Publish and update content for the jailbroken Kindle billboard verified in this workspace. Use when asked to push or show an image, text card, chart snapshot, memo, sign, schedule, dashboard, meme, or rasterized PDF page on the Kindle. This skill handles the host-side publish directory, 600x800 grayscale conversion, simple text-card rendering, static HTTP serving, and the device-specific rule that untethered delivery is pull-based: the Kindle must already be running its poll loop to fetch the latest current.png over Wi-Fi."
---

# Kindle Billboard

Use this skill to update the Kindle billboard without re-learning the device quirks.

## Workflow

1. Read [references/current-setup.md](references/current-setup.md) when delivery guarantees or device constraints matter.
2. For current-news meme runs, prepare a Tavily-backed plan first with [scripts/plan_daily_news_meme.py](scripts/plan_daily_news_meme.py).
3. Decide the transport:
   - For normal untethered updates: publish a new `current.png` on the host.
   - For immediate direct rendering: claim this path only if a direct on-device action actually ran, such as `Render Current Once` from KUAL or a USB/Wi-Fi shell command.
   - For host-driven push without waiting for the poller: use `tools/push-current-kindle.ps1` when SSH is reachable.
4. Publish content with [scripts/publish_kindle_billboard.py](scripts/publish_kindle_billboard.py).
5. Report the exact artifact path and whether delivery is guaranteed or only staged.

## Commands

Status:

```bash
python scripts/publish_kindle_billboard.py status
```

Publish a local image file or remote image URL:

```bash
python scripts/publish_kindle_billboard.py publish-file <path-or-url>
```

Publish a simple generated card:

```bash
python scripts/publish_kindle_billboard.py publish-text --title "Barn Notes" --body "Fence crew on south pasture at 18:00." --footer "Updated by agent"
```

Prepare a daily current-news meme brief with Tavily:

```bash
python scripts/plan_daily_news_meme.py
```

This expects `TAVILY_API_KEY` in the environment.

Publish a current-news meme card after an agent creates the joke and image:

```bash
python scripts/publish_kindle_billboard.py publish-news-meme --headline "..." --joke "..." --summary "..." --source-name "Reuters" --source-url "https://..." --image /absolute/path/to/news-meme.png --footer "OpenClaw daily cron"
```

Serve the published directory over local HTTP:

```bash
python scripts/publish_kindle_billboard.py serve
```

Publish a rotating playlist:

```bash
python scripts/publish_kindle_billboard.py publish-playlist <path-or-url> <path-or-url> <path-or-url>
```

Refresh the host-generated daylight window file:

```bash
python scripts/publish_kindle_billboard.py refresh-daylight
```

Ensure the Windows host HTTP loop is running in the background:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\kindle-host-serve.ps1 -Action ensure
```

Install the Windows-login Startup entry for that host helper:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-kindle-host-startup.ps1
```

Install the Kindle boot-time poller hook over Wi-Fi SSH:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-kindle-autostart.ps1
```

## Operating Rules

- Prefer overwriting the host-side `current.png` or `playlist.txt` on the host over trying to drive the Kindle UI.
- Keep output `600x800`; let the script do the final grayscale fit.
- Treat PDF as a host-side rasterization problem. If the host cannot rasterize the PDF, report the missing renderer instead of bluffing.
- If the Kindle is mounted as USB mass storage on Windows, compare the deployed `/mnt/us/billboard` and `/mnt/us/extensions/kindle-billboard` files against the repo before assuming Wi-Fi is broken.
- If the Kindle is still mounted as USB mass storage, say clearly that Wi-Fi delivery is only staged until the device is ejected and leaves drive mode.
- If the user asks for true host push, say clearly that plain USB mass storage is insufficient; use SSH over USBNetwork or Wi-Fi and render a local file on-device.
- If Wi-Fi SSH is listening but the current credentials are unknown, repair host access from mounted USB storage first by writing the host public key to `/mnt/us/usbnet/etc/authorized_keys`; only then keep debugging billboard runtime behavior.
- On this Windows host, prefer native `ssh.exe` and `scp.exe` for Kindle Wi-Fi work; WSL may fail LAN routing even when Windows can reach the device.
- Windows OpenSSH password auth can be automated here with `SSH_ASKPASS` plus `SSH_ASKPASS_REQUIRE=force`.
- After any password reset, verify it with a real password SSH login or by matching the live `/etc/shadow` hash against on-device `mkpasswd -m des`.
- If mounted usbnet storage already contains `/mnt/us/usbnet/auto`, remember that boot-time SSH is enabled. For this project, pair that with `USE_WIFI_SSHD_ONLY="true"` so the Kindle stays reachable after reboot without breaking normal USB mass-storage maintenance.
- Preserve LF line endings for `/mnt/us/billboard/config.env` and all on-device shell files. Do not use Windows text-writing helpers such as `Set-Content` to generate Kindle-side shell or sourced env files.
- When `Start Poller` appears to do nothing, inspect `/mnt/us/billboard/state/poller.pid`, `/mnt/us/billboard/state/poller.lock`, `/mnt/us/billboard/logs/poller.log`, and `/mnt/us/billboard/logs/kual-actions.log` before chasing network theories.
- Treat the KUAL footer toast as non-authoritative; use logs, PID/lock state, host GETs, and the screen as the real signals.
- If host push works but Wi-Fi polling does not, confirm the host `serve` process is still listening on `0.0.0.0:8765` before changing Kindle-side scripts.
- Be explicit about state:
  - `published`: the host artifact was updated
  - `delivered`: the Kindle is expected to fetch it because the poll loop is known to be running
  - `rendered-now`: a direct Kindle-side command completed
- Do not say "pushed to the Kindle" if only the host artifact changed and the Kindle poll loop state is unknown.
- Close visual validation with an actual image publish when the user cares about memes, charts, screenshots, or other raster content; a text card alone is not enough evidence.
- If `Render Current Once` appears dead but logs show the wrapper ran, check whether it accidentally honored `RENDER_ON_CHANGE=1`; manual render should force a redraw.
- Prefer SSH key auth for `push-current-kindle.ps1` and related helpers. Password auth is the fallback path.

## Decision Notes

- Use `publish-text` for quick notices, instructions, schedules, and low-effort dashboards.
- Use `publish-file` for charts, screenshots, memes, generated art, and already-rendered pages.
- Use `plan_daily_news_meme.py` when the user wants current-events humor, memes, or a cron-driven daily billboard sourced from fresh news.
- Use `publish-news-meme` when an external agent has already selected the story and created the joke or image.
- If the user asks for a web dashboard or PDF view, prefer server-side render to PNG rather than browser-kiosk behavior on the Kindle.
- If the user asks whether updates work while unplugged: yes when the Kindle is charged, on Wi-Fi, and already running `/mnt/us/billboard/poll-url.sh`.
- If the user asks whether updates work after a reboot: the Kindle-side poller auto-start hook is now installed and was verified on a real reboot. The host-side `serve` loop still needs to be running.
- If the user asks whether the Kindle can stay available while plugged into power: yes on wall power or a power bank. The default repo profile is daytime `CHARGING_INTERVAL_SECONDS=3600`, battery `BATTERY_INTERVAL_SECONDS=43200`, and `USE_SUSPEND=1`, and the poller now auto-starts on reboot on this device.
- If the user asks for sunrise/sunset behavior, prefer the host-generated `daylight.env` file and document `KINDLE_BILLBOARD_LATITUDE`, `KINDLE_BILLBOARD_LONGITUDE`, and `KINDLE_BILLBOARD_TIMEZONE` on the host.
- If the user asks to make the password be `kindle`, the smooth path is: mount USB storage, run `tools/install-kindle-ssh-key.ps1`, eject, then run `tools/set-kindle-root-password.ps1 -NewPassword kindle`.

## References

- [references/current-setup.md](references/current-setup.md): verified facts for this Kindle
- [references/daily-news-meme-workflow.md](references/daily-news-meme-workflow.md): Tavily-backed cron design for current-news memes
- [references/openclaw-hermes-prompt.md](references/openclaw-hermes-prompt.md): short copy/paste prompt for external agents
