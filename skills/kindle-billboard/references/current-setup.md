# Current Setup

Verified on `2026-04-12`.

## Device

- Model: Kindle `(7th Generation)` / `KT2, BASIC`
- Firmware: `5.12.2.2`
- Codename: `Bourbon/Wario`
- Jailbreak: present
- KUAL/MRPI/USBNetwork: installed

## Verified device-side tools

- `/usr/bin/fbink`
- `/usr/sbin/eips`
- `/usr/bin/curl`
- `/usr/bin/wget`
- `/usr/bin/lipc-set-prop`
- `/usr/bin/gasgauge-info`

## Installed Kindle-side files

On the Kindle user partition:

- `/mnt/us/billboard/show-url.sh`
- `/mnt/us/billboard/poll-url.sh`
- `/mnt/us/billboard/README.md`

## Proven path

This was proven live:

1. host served `billboard-test.png` over LAN HTTP
2. Kindle fetched it over `wlan0`
3. Kindle rendered it with `fbink`
4. user confirmed it was visible on-screen

Additional live observations from the same `2026-04-12` session:

- Host Wi-Fi IP in use: `192.168.50.131`
- Billboard URL in use: `http://192.168.50.131:8765/current.png`
- Kindle Wi-Fi IP observed in host logs/ARP: `192.168.50.162`
- Kindle USB serial observed from Windows PnP: `90C606064484096B`
- Mounted usbnet user storage contained `/mnt/us/usbnet/auto`
- After restarting the poller from KUAL, the host again saw successful `GET /current.png` requests over Wi-Fi at `17:33:56`, `17:34:19`, `17:35:10`, `17:35:12`, `17:38:12`, and `17:38:48` on `2026-04-12`
- A new host-side test card was published at `17:39:40`, but the user reported the Kindle screen still showed the older `17:32` card
- After the runtime fixes were redeployed, `Render Current Once` from KUAL rendered `Poller Afterparty Check`
- After `Start Poller` from KUAL, the host again saw fresh `GET /current.png` requests at `18:12:28` and `18:14:29`, and the Kindle advanced to `Wi-Fi Victory Lap`
- Mounted USB storage was later used to install the host public key into `/mnt/us/usbnet/etc/authorized_keys`
- Native Windows OpenSSH reached `root@192.168.50.162` with key auth after reboot; WSL routing was the blocker, not Kindle SSH itself
- The root password was set to `kindle` and verified with both a real password SSH login and an on-device `mkpasswd -m des` hash match
- `tools/push-current-kindle.ps1` was fixed to use native Windows `ssh.exe` and `scp.exe` for Wi-Fi, and direct host push rendered `current.png` immediately over SSH
- A real image card was published at `21:13:07` local time on `2026-04-12`, the host logged `GET /current.png` at `21:13:58`, and the Kindle was running the poller again on the wall-power profile
- When untethered polling appeared dead late in the session, the real blocker was the host `serve` loop not listening on `0.0.0.0:8765`; restarting the host server restored host-side `GET /current.png`
- `tools/install-kindle-autostart.ps1` installed `/etc/upstart/kindle-billboard.conf` and `/mnt/us/billboard/autostart.sh`
- The first upstart trigger attempt on `framework_ready` did not survive a real reboot; `started framework` did
- After the corrected install, a real reboot logged `2026-04-12 20:30:43 autostart invoked` followed by `started: 5226`
- After that reboot-driven autostart, the host again logged `GET /current.png` at `21:31:54`
- The Windows host now has `tools/kindle-host-serve.ps1` plus `tools/install-kindle-host-startup.ps1` to manage the Windows-login Startup entry
- On this device, when the poller is already running, a power-button sleep/wake cycle can effectively act like an on-demand refresh shortcut

Interpretation:

- Wi-Fi reachability and HTTP fetches are proven
- direct on-device rendering from KUAL is proven
- KUAL `Start Poller` is proven for untethered Wi-Fi updates
- the transport/render gap from the earlier session is closed
- Wi-Fi SSH on `192.168.50.162:22` is reachable from native Windows OpenSSH with both key auth and password auth
- direct host push over Wi-Fi SSH is proven, separate from the poller path
- the host `serve` process is part of the untethered contract; if it is down, poller debugging on the Kindle is a distraction
- Kindle boot-time poller auto-start is proven on a real reboot when the upstart job is attached to `started framework`

## Root causes resolved on `2026-04-12`

- stale on-device `billboard/*.sh` and `kual/kindle-billboard/*` files
- stale `/mnt/us/billboard/state/poller.pid` and `poller.lock`
- KUAL launcher actions that were too dependent on relative paths and direct script execution
- `/mnt/us/billboard/config.env` rewritten from Windows with CRLF line endings, which caused shell errors like `: not found`
- a dead host `serve` process on port `8765`, which made the poller look broken again even after Kindle-side fixes were done
- an initial upstart trigger on `framework_ready`, which loaded but did not actually fire on reboot for this custom job

## Practical lessons

- While the Kindle is mounted as USB mass storage, untethered Wi-Fi fetches are effectively paused. In that state, file comparison and deployment are the right checks, not host `GET /current.png` expectations.
- The KUAL footer message is not proof of success. Trust `kual-actions.log`, `poller.log`, PID/lock inspection, host-side `GET /current.png`, and the screen.
- `Render Current Once` is the shortest local runtime test, but final acceptance should include a real image publish because the target product is an image billboard, not a text-only sign.
- A manual render action must bypass change detection. On `2026-04-12`, the logs showed `Render Current Once` could run through KUAL yet still appear dead because it returned `unchanged` instead of redrawing the cached image.
- KindleTool upstream source shows serial prefix `90C6...` maps to device code `C6`, which is the pre-Wario default-password path for this Kindle model. The failed default-password login therefore points to changed auth state, not a bad serial parse.
- When Wi-Fi SSH is reachable but current credentials are unknown, mounted USB storage is still a valid repair path because USBNetwork reads `authorized_keys` from `/mnt/us/usbnet/etc/authorized_keys`.
- On this Windows host, prefer native `ssh.exe` and `scp.exe` for Wi-Fi Kindle work. WSL may fail LAN routing even when Windows can reach `192.168.50.162`.
- Windows OpenSSH password auth can be automated with `SSH_ASKPASS` plus `SSH_ASKPASS_REQUIRE=force`.
- After changing the Kindle root password, verify it with a real password SSH login or by comparing the live `/etc/shadow` hash to on-device `mkpasswd -m des`.
- The mounted usbnet package already had `auto` enabled. That explained why USB maintenance mode felt inconsistent. The better steady state for this billboard is `USE_WIFI="true"` with `USE_WIFI_SSHD_ONLY="true"` so boot-time SSH stays available without forcing Ethernet-over-USB mode for maintenance.
- For this device and firmware, the verified Kindle boot trigger is upstart `started framework`, not `framework_ready`.

## Important constraints

- Untethered updates are pull-based, not true push:
  - the Kindle must already be running `/mnt/us/billboard/poll-url.sh`
  - agents update the host-side `current.png`
- The host-side `serve` process must still be running on `0.0.0.0:8765`; direct SSH push does not keep the Wi-Fi poll loop alive by itself
- Direct immediate rendering is available from KUAL via `Render Current Once`
- Direct host-driven rendering is possible only when SSH is reachable over USBNetwork or Wi-Fi; plain mounted USB storage cannot update the live screen by itself
- Old Kindle TLS is weak; plain HTTP on trusted LAN is simplest
- PDF is not being rasterized on-device; convert to PNG/JPEG first

## Recommended host-side contract

- Canonical file: `current.png`
- Recommended canvas: `600x800`
- Recommended palette: grayscale
- Expose the file via static HTTP from a fixed URL

## Current default runtime profile

- `INTERVAL_SECONDS=60`
- `USE_SUSPEND=0`
- intended for a Kindle that mostly lives on wall power; the poller now auto-starts on reboot, and the host `serve` loop is managed by a Windows helper plus Startup entry

## Honest status rule

Do not claim "I pushed it to the Kindle" unless one of these is true:

1. `current.png` was updated and the Kindle poller is known to be running, or
2. a direct render command completed over USB/Wi-Fi SSH

## Immediate handoff

The shortest next-agent path is documented in [next-agent-handoff.md](next-agent-handoff.md).
