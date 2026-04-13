# Workspace Instructions

## Tavily
- Tavily research is enabled for this workspace.
- Prefer `tavily_search` plus `tavily_extract` for targeted fact checks, source verification, and narrow comparisons.
- Use `tavily_research` for broader landscape scans, multi-source synthesis, or when the user explicitly asks for research.
- Default `tavily_research` to `model="mini"` for inline agent calls.
- Treat `tavily_research` with `model="pro"` as a long-running async job. If the current tool wrapper cannot poll or stream and the call times out, do not keep retrying the same sync request.
- When `model="pro"` is needed, prefer one of these patterns:
  1. Split the task into smaller `mini` research calls.
  2. Fall back to `tavily_search` plus `tavily_extract`.
  3. Use Tavily async polling or streaming semantics when the available client supports `request_id`, polling, or SSE.
- Keep Tavily research prompts concise and well-scoped. For broad topics, decompose them into smaller sub-queries.
- Prefer official docs and primary sources when available.
- Do not silently downgrade or gloss over Tavily failures in critical workflows.
- If Tavily research fails in a workflow where research quality or completeness matters, surface the failure clearly, state whether the problem appears to be the wrapper, credentials, timeout budget, or Tavily itself, and treat it as an issue to work around explicitly.
- In critical workflows, prefer this order:
  1. Retry with a better-shaped Tavily request.
  2. Switch from sync `pro` calls to async polling or streaming.
  3. Use narrower Tavily calls only if they still preserve the task's intent.
  4. Fall back to non-research Tavily tools only with an explicit note that this is a degraded path.
- Only continue without blocking after a Tavily failure when the degraded path is clearly sufficient for the user's goal. Otherwise stop and report the blocker.

## Kindle Debugging
- If the Kindle is mounted as USB mass storage on Windows, compare the deployed `billboard/` and `extensions/kindle-billboard/` files against the repo before assuming USBNetwork access is required.
- If the Kindle is mounted as USB mass storage, do not expect live Wi-Fi polling or host-side `GET /current.png` until the device is safely ejected and back out of drive mode.
- If Wi-Fi SSH is listening but the current credentials are unknown, repair host access from mounted USB storage first by writing the host public key to `/mnt/us/usbnet/etc/authorized_keys`; only after that should you spend time on password resets or billboard runtime code.
- If Wi-Fi SSH is reachable from Windows but not from WSL, prefer native Windows `ssh.exe` and `scp.exe` for Kindle Wi-Fi work; do not burn time on WSL routing unless USB transport is the actual target.
- Windows OpenSSH password auth can be automated here with `SSH_ASKPASS` plus `SSH_ASKPASS_REQUIRE=force`; use that before declaring password-based Wi-Fi tooling blocked.
- After a root password change, verify it with a real password SSH login or by matching the live `/etc/shadow` hash against on-device `mkpasswd -m des`.
- For Wi-Fi failures, classify them in this order: host serving, host log `GET /current.png`, deployed-file drift on `/mnt/us`, then live Kindle render failure.
- Direct SSH push and Wi-Fi polling are separate checks. If host push works but the poller does not update, confirm the host is actually listening on `0.0.0.0:8765` before editing Kindle-side scripts.
- Use `tools\kindle-host-serve.ps1` to manage the host HTTP loop. Use `tools\install-kindle-host-startup.ps1` to install or remove the Windows-login Startup entry that reruns `-Action ensure`.
- Use `tools\install-kindle-autostart.ps1` for Kindle boot-time poller startup. On this firmware, the verified upstart trigger is `started framework`, not `framework_ready`.
- Define done for Wi-Fi debugging as: a newly published `current.png`, at least one host-side `GET /current.png` after that publish, and a visibly changed Kindle screen.
- If `Start Poller` or `Restart Poller` appears to do nothing, inspect persisted `/mnt/us/billboard/state/poller.pid` and `poller.lock` before blaming Wi-Fi; stale state on the user partition can survive restarts and block a new poller launch.
- Treat the KUAL footer toast as a weak signal only; `Starting Kindle Billboard Poller` does not prove the poller actually launched.
- For scripts launched from `/mnt/us`, prefer `/bin/sh script.sh` over direct script execution between helper scripts; USB mass-storage copies can leave Kindle-side execution behavior inconsistent even when the files are present.
- When debugging KUAL launcher actions, prefer absolute `/mnt/us/...` paths in `menu.json` params instead of relative paths, and add timestamped wrapper logging under `/mnt/us/billboard/logs/` before changing deeper runtime code.
- For Kindle shell files and `config.env`, preserve LF line endings and avoid Windows-authored `Set-Content` output for on-device `.sh` or sourced env files; CRLF in `/mnt/us` scripts or env files can produce silent KUAL no-ops or `: not found` shell errors.
- Close visual validation with at least one real image publish after text-card smoke tests; a text render alone does not prove the grayscale image pipeline.
- Plain USB mass-storage mode is not a true host-push transport. If the user wants the computer to push an image that appears immediately, use SSH over USBNetwork or Wi-Fi and render a local file on-device instead of waiting for `GET /current.png`.
- Prefer SSH key auth for host-push tooling on this project. Password auth is the fallback path, not the primary one.
- If Windows sees a Kindle USB device but you have neither a mounted drive letter nor a reachable SSH target, classify that as a transport-state blocker before debugging app logic; you cannot read fresh logs or do a live host push until one transport is actually usable.
- `Render Current Once` should bypass `RENDER_ON_CHANGE`; if it reuses the normal fetch path with change detection enabled, it can log `unchanged` and look dead even though the KUAL action ran.
- On this Windows host, USBNetwork push via `usbipd` also requires the Kindle bus to be shared/bound first; if `usbipd list` shows `Not shared`, fix that before blaming the billboard code.
