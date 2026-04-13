# Next Agent Handoff

Use this file to resume quickly. Do not restart the project from scratch.

## User intent

The user wants:

- a Kindle that behaves like a portable Wi-Fi billboard
- low-touch operation after setup
- AI agents on the ARM host to publish images, charts, notices, and daily news memes
- no recurring dependence on KUAL or USB after the one-time setup is stable

The user explicitly does **not** want the work framed around USB networking as the runtime model. USB maintenance is acceptable; recurring tethering is not.

## Current state

Verified on `2026-04-12`:

- Device: Kindle `(7th Generation)` / `KT2, BASIC`
- Firmware: `5.12.2.2`
- Jailbreak + KUAL + MRPI + USBNetwork installed
- Host Wi-Fi IP: `192.168.50.131`
- Host HTTP server listening on `0.0.0.0:8765`
- Billboard URL in use: `http://192.168.50.131:8765/current.png`
- Kindle Wi-Fi IP observed from host: `192.168.50.162`
- `Render Current Once` from KUAL rendered `Poller Afterparty Check`
- `Start Poller` from KUAL resumed Wi-Fi polling and advanced the screen to `Wi-Fi Victory Lap`
- Wi-Fi SSH on `192.168.50.162:22` is reachable from native Windows OpenSSH with key auth
- Root password is now `kindle`, and password auth was verified from Windows OpenSSH via `SSH_ASKPASS`
- `tools/push-current-kindle.ps1` now uses native Windows `ssh.exe` and `scp.exe` for Wi-Fi host push
- A real weather/news image was published at `21:13:07` local time on `2026-04-12`
- The host logged fresh `GET /current.png` at `21:11:58`, `21:12:58`, and `21:13:58` after the late-session host server restart
- `tools/install-kindle-autostart.ps1` installed a reboot-tested Kindle upstart hook
- The verified upstart trigger is `started framework`; `framework_ready` did not fire reliably for this custom job
- After a real reboot, `autostart.log` recorded `2026-04-12 20:30:43 autostart invoked` followed by `started: 5226`
- The host logged `GET /current.png` again at `21:31:54` after that reboot-driven autostart
- The Windows host now has `tools/kindle-host-serve.ps1` plus a Startup entry at `C:\Users\monro\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\kindle-host-serve.cmd`
- Mounted usbnet storage showed `/mnt/us/usbnet/auto` was already enabled

Relevant host log evidence in `artifacts/wifi-http.err.log`:

- `2026-04-12 18:12:28` `GET /current.png`
- `2026-04-12 18:14:29` `GET /current.png`
- `2026-04-12 21:11:58` `GET /current.png`
- `2026-04-12 21:12:58` `GET /current.png`
- `2026-04-12 21:13:58` `GET /current.png`

## Root causes that were fixed

1. The Kindle was not running the same `billboard/*.sh` and `kual/kindle-billboard/*` files as the repo.
2. `Start Poller` could be blocked by stale `/mnt/us/billboard/state/poller.pid` and `poller.lock`.
3. KUAL launcher actions were too dependent on relative paths and direct execution on `/mnt/us`.
4. `/mnt/us/billboard/config.env` had Windows CRLF line endings, which caused shell errors such as:

```text
/mnt/us/billboard/render-once.sh: /mnt/us/billboard/config.env: line 2:
: not found
```

## Important repo state

The current repo state that matters is in:

- `README.md`
- `billboard/README.md`
- `billboard/*.sh`
- `billboard/config.env.example`
- `kual/kindle-billboard/*`
- `skills/kindle-billboard/SKILL.md`
- `skills/kindle-billboard/references/current-setup.md`
- `tools/install-kindle-ssh-key.ps1`
- `tools/set-kindle-root-password.ps1`
- `tools/push-current-kindle.ps1`
- this handoff file

## Known-good maintenance rules

- If the Kindle is mounted as USB mass storage on Windows, compare the deployed `billboard/` and `extensions/kindle-billboard/` files against the repo before assuming Wi-Fi is broken.
- If the Kindle is still mounted as USB storage, treat host publishes as staged only; eject before expecting new `GET /current.png` traffic.
- Preserve LF line endings for `/mnt/us/billboard/config.env` and all `*.sh` files.
- Do not generate Kindle-side shell or sourced env files with Windows text writers such as PowerShell `Set-Content`.
- `Render Current Once` is the shortest on-device smoke test.
- `kual-actions.log` and `poller.log` are the first runtime logs to inspect when KUAL appears to do nothing.
- The KUAL footer status text is not authoritative evidence that a poller action completed.
- Before closing a visual fix, publish a real image or meme, not just a text card.
- If `Render Current Once` logs a run but the screen does not change, verify that manual render bypasses `RENDER_ON_CHANGE`; otherwise it can return `unchanged` and look dead.
- If Wi-Fi SSH is listening but the password is unknown, mounted USB storage can still repair host push by writing the host public key to `/mnt/us/usbnet/etc/authorized_keys`.
- The repo SSH helpers now prefer `~/.ssh/id_ed25519` and fall back to `KINDLE_SSH_PASSWORD` or an explicit `-SshPassword`.
- On this Windows host, prefer native `ssh.exe` and `scp.exe` for Wi-Fi Kindle work; WSL may fail LAN routing even when Windows can reach the device.
- Windows OpenSSH password auth can be automated with `SSH_ASKPASS` plus `SSH_ASKPASS_REQUIRE=force`.
- If direct host push works but untethered polling does not, check the host server before changing Kindle code. A dead `serve` process on `0.0.0.0:8765` is a host-serving blocker, not a Kindle render bug.
- The host `serve` helper is `tools/kindle-host-serve.ps1`; use `-Action ensure`, `-Action status`, and `-Action stop`.
- The Kindle boot hook installer is `tools/install-kindle-autostart.ps1`.
- For this Kindle, the sane appliance profile is `USE_WIFI="true"` plus `USE_WIFI_SSHD_ONLY="true"` with `/mnt/us/usbnet/auto` present. Without SSHD-only mode, `auto` can make USB maintenance look broken.

## What is still left

The transport/render path is now working. The next meaningful improvements are:

1. optional polish around wall-power behavior and long-running availability
2. if needed, promote the Windows login Startup entry into a machine-wide service or scheduled task
3. daily-news meme automation and cadence once appliance behavior is stable

## Current blocker

- No transport or auth blocker remains.
- The Kindle poller auto-starts on reboot now, and the host `serve` loop is covered at Windows login by the Startup entry.
- Remaining gap only if the host must serve before any user login; that would need a service or scheduled-task version of the helper.

## Suggested next message to the user

Use something this direct:

1. say that direct render, untethered Wi-Fi polling, and reboot-time poller auto-start are all working
2. say the remaining optional improvement is making host serving start before Windows login, not more Kindle debugging
3. note that wall power is fine, the current config polls every 60 seconds without intentional suspend
