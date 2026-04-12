---
name: kindle-billboard
description: "Publish and update content for the jailbroken Kindle billboard verified in this workspace. Use when asked to push or show an image, text card, chart snapshot, memo, sign, schedule, dashboard, meme, or rasterized PDF page on the Kindle. This skill handles the host-side publish directory, 600x800 grayscale conversion, simple text-card rendering, static HTTP serving, and the device-specific rule that untethered delivery is pull-based: the Kindle must already be running its poll loop to fetch the latest current.png over Wi-Fi."
---

# Kindle Billboard

Use this skill to update the Kindle billboard without re-learning the device quirks.

## Workflow

1. Read [references/current-setup.md](references/current-setup.md) when delivery guarantees or device constraints matter.
2. Decide the transport:
   - For normal untethered updates: publish a new `current.png` on the host.
   - For immediate direct rendering: only claim this path if USB or Wi-Fi SSH is actually available.
3. Publish content with [scripts/publish_kindle_billboard.py](scripts/publish_kindle_billboard.py).
4. Report the exact artifact path and whether delivery is guaranteed or only staged.

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

Serve the published directory over local HTTP:

```bash
python scripts/publish_kindle_billboard.py serve
```

## Operating Rules

- Prefer overwriting the host-side `current.png` over trying to drive the Kindle UI.
- Keep output `600x800`; let the script do the final grayscale fit.
- Treat PDF as a host-side rasterization problem. If the host cannot rasterize the PDF, report the missing renderer instead of bluffing.
- Be explicit about state:
  - `published`: the host artifact was updated
  - `delivered`: the Kindle is expected to fetch it because the poll loop is known to be running
  - `rendered-now`: a direct Kindle-side command completed
- Do not say "pushed to the Kindle" if only the host artifact changed and the Kindle poll loop state is unknown.

## Decision Notes

- Use `publish-text` for quick notices, instructions, schedules, and low-effort dashboards.
- Use `publish-file` for charts, screenshots, memes, generated art, and already-rendered pages.
- If the user asks for a web dashboard or PDF view, prefer server-side render to PNG rather than browser-kiosk behavior on the Kindle.
- If the user asks whether updates work while unplugged: yes only when the Kindle is charged, on Wi-Fi, and already running `/mnt/us/billboard/poll-url.sh`.

## References

- [references/current-setup.md](references/current-setup.md): verified facts for this Kindle
- [references/openclaw-hermes-prompt.md](references/openclaw-hermes-prompt.md): short copy/paste prompt for external agents
