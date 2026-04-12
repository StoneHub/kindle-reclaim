# Next Agent Handoff

Use this file to resume quickly. Do not restart the project from scratch.

## User intent

The user wants:

- a Kindle that behaves like a portable Wi-Fi billboard
- low-touch operation after setup
- AI agents on the ARM host to publish images, charts, notices, and daily news memes
- no recurring dependence on KUAL or USB after the one-time setup is stable

The user explicitly does **not** want the work framed around USB networking as the long-term solution. USB networking is only the one-time maintenance path for shell access.

## Verified so far

Verified on `2026-04-12`:

- Device: Kindle `(7th Generation)` / `KT2, BASIC`
- Firmware: `5.12.2.2`
- Jailbreak + KUAL + MRPI + USBNetwork installed
- Host Wi-Fi IP: `192.168.50.131`
- Host HTTP server listening on `0.0.0.0:8765`
- Billboard URL in use: `http://192.168.50.131:8765/current.png`
- Kindle Wi-Fi IP observed from host: `192.168.50.162`
- Direct Wi-Fi fetch + render worked earlier with a test image
- After a hard reboot, the Kindle returned to the normal home screen and KUAL remained usable
- After `Restart Poller` from KUAL, the host again saw successful `GET /current.png` requests from `192.168.50.162`

Relevant host log evidence:

- `artifacts/wifi-http.err.log`
- successful `GET /current.png` at:
  - `2026-04-12 17:33:56`
  - `2026-04-12 17:34:19`
  - `2026-04-12 17:35:10`
  - `2026-04-12 17:35:12`
  - `2026-04-12 17:38:12`
  - `2026-04-12 17:38:48`

## What failed

The system is **not** yet proven reliable end to end.

Observed failure:

1. A new host-side card was published at `2026-04-12 17:39:40`.
2. Host artifacts changed correctly:
   - `artifacts/publish/current.png`
   - `artifacts/publish/current.json`
3. The Kindle was expected to fetch the new image on the next poll.
4. The user reported the screen still showed the older `17:32` card instead of the newer `17:39` card.

Implication:

- HTTP fetches are happening
- repaint/render behavior after the restarted poller is not yet trustworthy

## Important repo state

The current repo state that matters is in:

- `billboard/config.env.example`
- `billboard/show-url.sh`
- `billboard/status.sh`
- `billboard/README.md`
- `tools/deploy-kindle-billboard.ps1`
- `README.md`
- `skills/kindle-billboard/references/current-setup.md`
- this handoff file

These changes harden the runtime:

- fetch timeout bounds
- retry count
- skip re-render when the image is unchanged
- richer status output
- deploy helper writes `config.env` and can start the poller

But:

- these updated Kindle-side scripts were **not** redeployed to the device after the latest edits
- do not assume the running device matches the current repo

## Most likely causes

Treat these as hypotheses, not facts:

1. The Kindle is still running older `billboard/*.sh` files from before the latest hardening.
2. The poller is fetching successfully but the on-device render step is failing or returning early.
3. The poller was restarted from KUAL, but the screen state/UI interactions left the visible frame stale.
4. The device `config.env` on the Kindle has older values than the repo expects.

## Fastest path to finish

Do not start with Tavily or news content. First close the transport/render gap.

### Step 1: get one-time device access again

Preferred path:

- have the user reconnect the Kindle in USBNetwork mode one more time
- use the existing deploy helper or direct USB shell access
- redeploy the current `billboard/` and `kual/` files from the repo

Avoid telling the user USB networking is the runtime model. It is only the maintenance path.

### Step 2: verify directly on-device

Once shell access exists, run:

```sh
/mnt/us/billboard/status.sh
tail -n 50 /mnt/us/billboard/logs/poller.log
/mnt/us/billboard/show-url.sh http://192.168.50.131:8765/current.png
```

Need to learn:

- whether `show-url.sh` still repaints immediately
- whether poller log shows fetch-only success or render failures
- whether `config.env` matches the expected URL and interval

### Step 3: only then restore unattended mode

After direct render works again:

- start the poller
- publish one clearly new card
- confirm the screen changes

### Step 4: only after stable repaint, add appliance behavior

The user wants this to behave like a device, not an app they manually reopen.

After reliable repaint is proven:

- add a boot-time launcher path
- likely an Upstart job or equivalent startup hook modeled after:
  - `vendor/Kindle-Weather-Dashboard/Kindle/etc/upstart/startup.conf`

Do **not** enable boot-time auto-start until the current poller/render path is solid.

## Operational notes for the next agent

- The Kindle taking over the screen while the poller is running is expected behavior.
- A hard reboot returned the device to normal Kindle UI.
- The host server is already running; do not waste time rebuilding that.
- The current public repo exists at:
  - `https://github.com/StoneHub/kindle-reclaim`

## Suggested next message to the user

Use something this direct:

1. explain that Wi-Fi fetch is proven but repaint is not
2. say the shortest path is one more USBNetwork maintenance pass to redeploy the updated scripts and inspect `poller.log`
3. promise that after that, the focus is boot-time appliance behavior and real Wi-Fi updates, not KUAL babysitting
