# claude-usage-tracker

macOS menu bar widget that shows your Claude usage in real time, mirrored from `claude.ai/settings/usage`. The icon is a Claude-mascot "battery" that drains as you burn through your 5-hour block.

> **Linux (Arch / Omarchy)**: A Waybar module port is available on the `linux-port` branch. See [Linux install](#linux-arch--omarchy) below.

> **Disclaimer:** Not affiliated with, endorsed by, or sponsored by Anthropic. Claude is a trademark of Anthropic PBC. This app calls an undocumented internal endpoint that Anthropic could change or block at any time.

## Install

1. Download **[ClaudeUsageTracker.zip](https://github.com/eriklissinger/claude-usage-tracker/releases/latest)** from the latest release
2. Unzip and drag `ClaudeUsageTracker.app` to your `/Applications` folder
3. Right-click the app → **Open** (required once — macOS warns on first launch because the app isn't notarized)
4. The icon appears in your menu bar immediately

**To launch on login:** System Settings → General → Login Items → add `ClaudeUsageTracker`.

## Requirements

- macOS 13+
- Google Chrome
- Logged in to `claude.ai` in Chrome's `Default` profile

> **Current limitation:** while Brave / Edge use a similar cookie scheme, this repo currently reads only Google Chrome's `Default` profile path and `Chrome Safe Storage` keychain item.

## First-launch Keychain prompt

On first sync you'll see:

> "ClaudeUsageTracker wants to use your confidential information stored in 'Chrome Safe Storage' in your keychain."

Click **Always Allow** to silence it permanently. This is how the app reads your Chrome cookies to authenticate with claude.ai — no credentials are stored by the app.

## What it shows

- **5-hour block** — same percentage as `claude.ai/settings/usage`, updated every 60s
- **Weekly window** — same, account-wide (claude.ai, Claude Code, MCP, etc.)
- **Per-model and top-project breakdown** for the current block (Claude Code only — from local transcripts)
- **Reset countdowns** with absolute reset time

## Right-click menu

- **Sync now** — force an immediate poll
- **Refresh transcripts** — force a re-scan of local JSONL files

## How it works

On launch and every 60s the app reads cookies from Chrome's local `Default` profile, decrypts them via the macOS Keychain, and calls the same endpoint `claude.ai/settings/usage` uses. Local Claude Code transcripts (`~/.claude/projects/**/*.jsonl`) are watched with FSEvents for per-model / top-project breakdowns and as a fallback source for reset countdown timing.

If live sync fails (logged out, Chrome not installed, endpoint changes), the menu bar can keep showing the last fresh live value briefly. Once sync is stale, the menu bar falls back to `—`, while transcript-derived reset countdowns and breakdown rows can still appear in the popover.

## Build from source

Requires Swift / Xcode Command Line Tools.

```sh
git clone https://github.com/eriklissinger/claude-usage-tracker
cd claude-usage-tracker
./scripts/build-app.sh release
open ./build/ClaudeUsageTracker.app
```

### Dev notes

- `./scripts/build-app.sh` is the intended local run path: it builds the binary, assembles the `LSUIElement` app bundle, and ad-hoc signs it. A plain `swift build` binary is not equivalent for menu bar app behavior.
- `swift run cct-parse` prints transcript-derived totals plus active 5-hour / 7-day windows. It's useful for parser and window-logic debugging.

## Linux (Arch / Omarchy)

> **Status**: alpha — port lives on the `linux-port` branch. The Linux build is a Waybar custom module that polls claude.ai every 60s using your local Chromium-family browser session.

### Requirements
- Arch Linux or Omarchy
- Waybar
- One of: Google Chrome, Chromium, Brave, Edge, Vivaldi, Opera (Firefox not supported — different cookie scheme)
- Logged in to claude.ai in that browser
- `uv` (Python project manager): `curl -LsSf https://astral.sh/uv/install.sh | sh`
- secret-service backend (gnome-keyring or kwallet) — comes with most Linux desktops

### Install

```sh
git clone https://github.com/eriklissinger/claude-usage-tracker
cd claude-usage-tracker
git checkout linux-port
bash scripts/install-linux.sh
```

Then run `claude-usage-tracker doctor` to verify your environment.

### How it works

Each Waybar tick (every 60s) runs `claude-usage-tracker render-waybar`. That command reads cookies from the most recent Chromium-family browser profile via libsecret, calls `claude.ai/settings/usage`, scans local Claude Code transcripts at `~/.claude/projects/`, and emits Waybar-compatible JSON to stdout.

Notifications fire via `notify-send` at configurable thresholds (default: 50%, 75%, 90% of both the 5h block and weekly window).

### Config

`~/.config/claude-usage-tracker/config.toml` (created on first run, defaults provided). Settings:

- `browser_mode`: `auto` (default), `chrome`, `chromium`, `brave`, etc.
- `profile_override`: profile name to force (e.g. `"Profile 1"`).
- `refresh_interval_seconds`: 60 (matches Waybar interval).
- `[notifications]` thresholds and toggle.

### Why no API key?

The Linux port mirrors the macOS app: it uses your authenticated browser session (libsecret-decrypted cookies). An API-key alternative is candidate scope for v2 but explicitly out of scope for v1.

### Troubleshooting

- `—` in the bar: run `claude-usage-tracker doctor` and read the report.
- Keyring unlock prompt every poll: unlock the keyring permanently in your DE settings.
- `usage-critical` class never fires: bump thresholds in `config.toml`.
- To force-refresh: right-click the icon (sends `SIGRTMIN+11` to Waybar).

### Disclaimer

Same as macOS — calls an undocumented internal endpoint. Anthropic could change or block it at any time.

## License

[MIT](./LICENSE)
