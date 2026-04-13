# Kindle Billboard

Minimal Kindle-side client for a jailbroken Kindle that:

- fetches a raster image from a URL
- renders it full-screen with `fbink` or `eips`
- optionally loops with suspend/wake between refreshes
- skips refreshes when the fetched image has not changed
- bounds fetch time and retries so Wi-Fi hiccups do not hang the loop

## Verified

Verified on `2026-04-12` on:

- Kindle `(7th Generation)` / `KT2, BASIC`
- firmware `5.12.2.2`
- codename `Bourbon/Wario`

Live proof completed:

- Kindle fetched `http://192.168.50.131:8765/billboard-test.png` over Wi-Fi
- Kindle rendered it with `fbink`
- `Render Current Once` from KUAL rendered the current host card after the runtime fixes
- `Start Poller` from KUAL resumed Wi-Fi polling and advanced the screen to a newly published card

## Files

- `show-url.sh`: one-shot fetch + render
- `show-file.sh`: one-shot local-file render, for SSH-driven host push
- `poll-url.sh`: repeated refresh loop, with RTC suspend when available
- `start-poller.sh`: safe background launcher with PID/log handling
- `stop-poller.sh`: clean stop helper
- `restart-poller.sh`: restart helper
- `render-once.sh`: render current URL once without starting the loop
- `status.sh`: print local runtime state
- `autostart.sh`: boot-time hook that starts the poller after framework startup
- `kindle-billboard-upstart.conf`: Kindle upstart job template for boot-time poller start
- `config.env.example`: default on-device config template

## Runtime Behavior

The hardened default behavior is:

- fetch timeout: `30s`
- fetch retries: `2`
- render only on change: enabled
- poll interval: `60s`
- suspend between polls: disabled

This keeps the wall-power appliance responsive while still avoiding unnecessary e-ink refreshes and hanging HTTP requests.

Additional hardening verified in this workspace:

- KUAL wrappers dispatch through `/bin/sh`
- helper scripts call each other through `/bin/sh` instead of relying on direct execute behavior on `/mnt/us`
- stale `state/poller.pid` and `state/poller.lock` are treated as stale unless they actually belong to `poll-url.sh`
- Kindle boot-time auto-start was verified with an upstart job on `started framework`

## Usage

One-shot:

```sh
/mnt/us/billboard/show-url.sh http://your-host:8765/image.png
/mnt/us/billboard/show-file.sh /mnt/us/billboard/push/current.png
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

`Render Current Once` is the shortest on-device smoke test. It should force a redraw of the current host image even when the cached image bytes have not changed. If it fails, fix the local runtime before debugging Wi-Fi polling.

## Deploy

Host-side deploy helper:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy-kindle-billboard.ps1 -StartPoller
```

This copies:

- `billboard/*` -> `/mnt/us/billboard`
- `kual/kindle-billboard/*` -> `/mnt/us/extensions/kindle-billboard`

It also rewrites `/mnt/us/billboard/config.env` to the active host URL and can start the poller immediately over USB networking.

For the host HTTP loop on Windows, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\kindle-host-serve.ps1 -Action ensure
```

To install the Windows-login Startup entry that reruns that helper:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-kindle-host-startup.ps1
```

For Kindle boot-time auto-start over Wi-Fi SSH, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install-kindle-autostart.ps1
```

If you maintain the Kindle over plain USB mass storage instead of USB networking:

- do not expect live Wi-Fi fetches while the Kindle is mounted as a USB drive; eject first, then check for new host `GET /current.png`
- preserve LF line endings in `/mnt/us/billboard/config.env` and all `*.sh` files
- avoid PowerShell `Set-Content` or similar Windows text rewrites for on-device shell files
- if `Start Poller` appears to do nothing, inspect `/mnt/us/billboard/state/poller.pid`, `/mnt/us/billboard/state/poller.lock`, `/mnt/us/billboard/logs/poller.log`, and `/mnt/us/billboard/logs/kual-actions.log`
- do not treat the KUAL footer message as proof that a poller action completed
- once text smoke tests pass, publish at least one real image to validate the intended billboard path
- plain mounted USB storage is not itself a live render transport; for immediate host-driven renders use SSH and `show-file.sh`
- if direct host push works but the poller does not update, check the host first and confirm something is still listening on `0.0.0.0:8765`

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

On wall power, the Kindle can stay available as a responsive appliance with the default `60s` poll interval and `USE_SUSPEND=0`. Boot-time poller auto-start is now installed and reboot-tested on this device. The host-side `serve` process still needs to be running, and the repo now includes a Windows helper plus a user Startup entry for that.

For a wired host-push path from Windows, use [..\tools\push-current-kindle.ps1](..\tools\push-current-kindle.ps1). It copies the current published image to `/mnt/us/billboard/push/current.png` over SSH and runs `show-file.sh` immediately.

If SSH on Wi-Fi is reachable but current credentials are unknown, repair auth from mounted USB storage first:

1. run [..\tools\install-kindle-ssh-key.ps1](..\tools\install-kindle-ssh-key.ps1) while the Kindle is mounted as storage
2. eject the Kindle back out of drive mode
3. run [..\tools\set-kindle-root-password.ps1](..\tools\set-kindle-root-password.ps1) to set the root password to `kindle` if you still want password auth
4. use [..\tools\push-current-kindle.ps1](..\tools\push-current-kindle.ps1) for immediate renders

The SSH helpers prefer `~/.ssh/id_ed25519` when it exists and fall back to `KINDLE_SSH_PASSWORD` or an explicit `-SshPassword`.

On this Windows host, prefer native `ssh.exe` and `scp.exe` for Wi-Fi Kindle work. WSL can still help with USB transport, but it may fail LAN routing even when Windows can reach the Kindle over Wi-Fi.

For this specific Kindle, a stable always-on profile is:

- `/mnt/us/usbnet/auto` present
- `USE_WIFI="true"`
- `USE_WIFI_SSHD_ONLY="true"`

That keeps Wi-Fi SSH available after reboot without hijacking normal USB mass storage the next time the Kindle is plugged in for maintenance.
