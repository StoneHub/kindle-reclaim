# Kindle Billboard

Minimal Kindle-side client for a jailbroken Kindle that:

- fetches a raster image from a URL
- renders it full-screen with `fbink` or `eips`
- optionally loops with suspend/wake between refreshes

## Verified

Verified on `2026-04-12` on:

- Kindle `(7th Generation)` / `KT2, BASIC`
- firmware `5.12.2.2`
- codename `Bourbon/Wario`

Live proof completed:

- Kindle fetched `http://192.168.50.131:8765/billboard-test.png` over Wi-Fi
- Kindle rendered it with `fbink`

## Files

- `show-url.sh`: one-shot fetch + render
- `poll-url.sh`: repeated refresh loop, with RTC suspend when available
- `start-poller.sh`: safe background launcher with PID/log handling
- `stop-poller.sh`: clean stop helper
- `restart-poller.sh`: restart helper
- `render-once.sh`: render current URL once without starting the loop
- `status.sh`: print local runtime state
- `config.env.example`: default on-device config template

## Usage

One-shot:

```sh
/mnt/us/billboard/show-url.sh http://your-host:8765/image.png
```

Loop:

```sh
cp /mnt/us/billboard/config.env.example /mnt/us/billboard/config.env
# edit BILLBOARD_URL if needed
/mnt/us/billboard/start-poller.sh
```

Stop a running loop cleanly:

```sh
/mnt/us/billboard/stop-poller.sh
```

Status:

```sh
/mnt/us/billboard/status.sh
```

## KUAL

The repo also includes a KUAL extension under `kual/kindle-billboard`.

Install it to:

```sh
/mnt/us/extensions/kindle-billboard
```

Menu actions:

- `Start Poller`
- `Render Current Once`
- `Restart Poller`
- `Stop Poller`

## Deploy

Host-side deploy helper:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy-kindle-billboard.ps1
```

This copies:

- `billboard/*` -> `/mnt/us/billboard`
- `kual/kindle-billboard/*` -> `/mnt/us/extensions/kindle-billboard`

## Important limits

- `PNG/JPEG/GIF/BMP/PNM`: yes
- `PDF`: no on-device rasterization here; convert server-side first
- Modern `HTTPS`: may fail on old Kindle `curl`/`wget` because of TLS age
- `Tailscale`: the Kindle is not joining your tailnet in this setup; expose the content on a LAN IP, or through a subnet router/proxy reachable from local Wi-Fi

## Recommendation

For your use case:

1. server/agent renders `600x800` grayscale PNG
2. Kindle pulls it over local Wi-Fi
3. use `start-poller.sh` or the KUAL launcher for day-to-day operation
4. if you want a more elaborate scheduler/HTTPS handling, adapt `kindle-dash` rather than reflashing the OS
