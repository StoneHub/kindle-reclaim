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
- After restarting the poller from KUAL, the host again saw successful `GET /current.png` requests over Wi-Fi at `17:33:56`, `17:34:19`, `17:35:10`, `17:35:12`, `17:38:12`, and `17:38:48` on `2026-04-12`
- A new host-side test card was published at `17:39:40`, but the user reported the Kindle screen still showed the older `17:32` card

Interpretation:

- Wi-Fi reachability and HTTP fetches are proven
- screen repaint after a poller restart is not yet proven reliable
- the current on-device scripts may be older than the latest repo hardening, because the updated `billboard/*.sh` files were not redeployed to the device after the latest changes

## Important constraints

- Untethered updates are pull-based, not true push:
  - the Kindle must already be running `/mnt/us/billboard/poll-url.sh`
  - agents update the host-side `current.png`
- Direct immediate rendering after unplugging USB is not available unless Wi-Fi SSH is enabled/configured
- Old Kindle TLS is weak; plain HTTP on trusted LAN is simplest
- PDF is not being rasterized on-device; convert to PNG/JPEG first

## Recommended host-side contract

- Canonical file: `current.png`
- Recommended canvas: `600x800`
- Recommended palette: grayscale
- Expose the file via static HTTP from a fixed URL

## Honest status rule

Do not claim "I pushed it to the Kindle" unless one of these is true:

1. `current.png` was updated and the Kindle poller is known to be running, or
2. a direct render command completed over USB/Wi-Fi SSH

## Immediate handoff

The shortest next-agent path is documented in [next-agent-handoff.md](next-agent-handoff.md).
