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
