# claude-usage-tracker

macOS menu bar widget that shows your Claude usage in real time, mirrored from `claude.ai/settings/usage`. The icon is a Claude-mascot "battery" that drains as you burn through your 5-hour block.

## What it shows

- **5-hour block** — same percentage you'd see on `claude.ai/settings/usage`, polled live every 60s.
- **Weekly window** — same. Account-wide across claude.ai, Claude Code, MCP, etc.
- **Per-model and top-project breakdown** for the current 5-hour block. (Claude Code only — derived from local transcripts.)
- **Reset countdowns** with absolute reset time.

## How it works

Two data sources, fused:

1. **Live sync from claude.ai** (the percentages). On launch and every 60s, the app reads cookies from your Chrome profile, decrypts them via your macOS Keychain, and calls `https://claude.ai/api/organizations/{org}/usage` — the same endpoint the settings page uses. The `five_hour.utilization` and `seven_day.utilization` fields drive the displayed percentages, so they always match what the website shows.
2. **Local transcripts** (the breakdowns). Walks `~/.claude/projects/**/*.jsonl`, watches with FSEvents, and aggregates per-model / per-project NCU within the current 5-hour block. Used only for the breakdown rows; the headline percentages come from #1.

If sync fails (Chrome not installed, logged out, cookie expired, endpoint changes), the app falls back to a local NCU approximation from the transcripts and keeps going.

## Requirements

- macOS 13+
- Google Chrome (or a Chromium variant — Brave/Edge use the same cookie scheme; Safari and Firefox do not work)
- Logged in to `claude.ai` in Chrome
- A Claude Code installation that's writing transcripts to `~/.claude/projects/`

## First-launch behavior

The first sync triggers a one-time macOS Keychain prompt:

> "ClaudeUsageTracker wants to use your confidential information stored in 'Chrome Safe Storage' in your keychain."

Click **Always Allow** to silence it permanently. If you click Deny, the live sync is disabled and the app falls back to the local transcript approximation.

## Build & install

```sh
./scripts/build-app.sh release
open ./build/ClaudeUsageTracker.app
```

The build script does ad-hoc codesigning, so first launch may need a right-click → Open to bypass Gatekeeper. To launch on login, drag the `.app` into System Settings → General → Login Items.

## Settings

Right-click the menu bar icon for:

- **Plan** — Pro / Max 5× / Max 20× (only affects the local-transcript NCU caps; live-synced percentages don't depend on this)
- **Calibrate weekly reset** — manual override for the weekly window if you don't trust the live sync
- **Sync claude.ai now** — force an immediate poll
- **Refresh transcripts** — force a re-scan of local JSONL files

## Files written

- `~/Library/Preferences/com.eriklissinger.ClaudeUsageTracker.plist` — plan tier + weekly reset override
- `/tmp/cct_cookies_*.sqlite` — temporary copy of Chrome's cookie DB during each sync (deleted immediately after)

No other state. No analytics. No external services beyond `claude.ai` itself.

## Architecture

See [`docs/DESIGN.md`](./docs/DESIGN.md) for the full design notes (data model, NCU math, weekly-window detection, etc.).

## License

[MIT](./LICENSE)
