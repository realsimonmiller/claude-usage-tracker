# claude-usage-tracker

Shows your Claude usage in real time, pulled live from `claude.ai/settings/usage`.

- **macOS**: menu bar widget with a draining mascot battery icon
- **Linux (Arch / Omarchy)**: Waybar custom module with progress bars and threshold notifications

> **Disclaimer:** Not affiliated with, endorsed by, or sponsored by Anthropic. Claude is a trademark of Anthropic PBC. This app calls an undocumented internal endpoint that Anthropic could change or block at any time.

---

## macOS

### Install

1. Download **[ClaudeUsageTracker.zip](https://github.com/realsimonmiller/claude-usage-tracker/releases/latest)** from the latest release
2. Unzip and drag `ClaudeUsageTracker.app` to your `/Applications` folder
3. Right-click the app → **Open** (required once — macOS warns on first launch because the app isn't notarized)
4. The icon appears in your menu bar immediately

**To launch on login:** System Settings → General → Login Items → add `ClaudeUsageTracker`.

### Requirements

- macOS 13+
- Google Chrome, logged in to `claude.ai` in the `Default` profile

### First-launch Keychain prompt

On first sync you'll see:

> "ClaudeUsageTracker wants to use your confidential information stored in 'Chrome Safe Storage' in your keychain."

Click **Always Allow** to silence it permanently. This is how the app reads your Chrome cookies to authenticate with claude.ai — no credentials are stored by the app.

### What it shows

- **5-hour block** — same percentage as `claude.ai/settings/usage`, updated every 60s
- **Weekly window** — same, account-wide (claude.ai, Claude Code, MCP, etc.)
- **Per-model and top-project breakdown** for the current block (Claude Code only — from local transcripts)
- **Reset countdowns** with absolute reset time

### Right-click menu

- **Sync now** — force an immediate poll
- **Refresh transcripts** — force a re-scan of local JSONL files

### How it works

On launch and every 60s the app reads cookies from Chrome's local `Default` profile, decrypts them via the macOS Keychain, and calls the same endpoint `claude.ai/settings/usage` uses. Local Claude Code transcripts (`~/.claude/projects/**/*.jsonl`) are watched with FSEvents for per-model / top-project breakdowns and as a fallback source for reset countdown timing.

If live sync fails (logged out, Chrome not installed, endpoint changes), the menu bar falls back to `—`, while transcript-derived reset countdowns and breakdown rows can still appear in the popover.

### Build from source

Requires Swift / Xcode Command Line Tools.

```sh
git clone https://github.com/realsimonmiller/claude-usage-tracker
cd claude-usage-tracker
./scripts/build-app.sh release
open ./build/ClaudeUsageTracker.app
```

**Dev notes:**
- `./scripts/build-app.sh` builds the binary, assembles the `LSUIElement` app bundle, and ad-hoc signs it. A plain `swift build` binary is not equivalent for menu bar app behavior.
- `swift run cct-parse` prints transcript-derived totals plus active 5-hour / 7-day windows. Useful for parser and window-logic debugging.

---

## Linux (Arch / Omarchy)

Waybar custom module on the `linux-port` branch. Shows live usage with Unicode progress bars, threshold notifications via `notify-send`, and a click-to-open settings GUI.

### Requirements

- Arch Linux or Omarchy
- Waybar
- One of: Google Chrome, Chromium, Brave, Edge, Vivaldi, Opera (Firefox not supported — different cookie scheme)
- Logged in to claude.ai in that browser
- `uv` (Python project manager): `curl -LsSf https://astral.sh/uv/install.sh | sh`
- secret-service backend (gnome-keyring or kwallet) — standard on most Linux desktops

### Install

```sh
git clone https://github.com/realsimonmiller/claude-usage-tracker
cd claude-usage-tracker
git checkout linux-port
bash scripts/install-linux.sh
```

Then run `claude-usage-tracker doctor` to verify your environment.

### What it shows

The Waybar bar shows `󰚩 19%` (icon + 5h block percentage). Hovering shows:

```
5-HOUR BLOCK
████░░░░░░░░░░░░░░░░  19%
resets in 4h 47m · 8:30 PM

WEEKLY WINDOW
██░░░░░░░░░░░░░░░░░░  11%
resets in 5d 10h · Sun 2:00 AM

CLAUDE CODE — BY MODEL
Sonnet      ████████████░░░░░░░░  58%

CLAUDE CODE — TOP PROJECT
my-project  ████████████████████  100%
```

### Interactions

- **Left-click** — opens the notification settings GUI (configure thresholds, enable/disable)
- **Right-click** — force-refreshes the widget immediately (sends `SIGRTMIN+11` to Waybar)

### Notifications

`notify-send` fires when you cross configured thresholds on the 5h block or weekly window. Defaults: 50%, 75%, 90%. Deduped per reset window — fires once per crossing, not every poll.

Click the widget to open the settings GUI and change thresholds.

### How it works

Each Waybar tick (every 60s) runs `claude-usage-tracker render-waybar`. That command:

1. Finds your most recent Chromium-family browser profile
2. Reads and decrypts cookies from the local SQLite database via libsecret
3. Calls `https://claude.ai/api/organizations/{org_id}/usage`
4. Scans local Claude Code transcripts at `~/.claude/projects/` for model/project breakdowns
5. Emits Waybar-compatible JSON to stdout

### Config

`~/.config/claude-usage-tracker/config.toml` (created on first run with defaults). Key settings:

```toml
browser_mode = "auto"          # or "chrome", "chromium", "brave", etc.
# profile_override = "Profile 1"  # force a specific profile

[notifications]
enabled = true
block_thresholds = [50, 75, 90]   # 5h block %
week_thresholds = [50, 75, 90]    # weekly window %
```

### CLI commands

```sh
claude-usage-tracker render-waybar   # emit Waybar JSON (used by Waybar exec)
claude-usage-tracker doctor          # diagnose browser, keyring, transcript root
claude-usage-tracker settings-gui   # open notification settings window
```

### Troubleshooting

| Symptom | Fix |
|---|---|
| `—` in the bar | Run `claude-usage-tracker doctor` and read the report |
| HTTP 403 error | Make sure you're logged in to claude.ai in Chrome/Chromium |
| Keyring prompt every poll | Unlock the keyring permanently in your DE settings |
| No model/project breakdown | Only appears when Claude Code transcript activity exists in the current 5h window |
| Widget not appearing | Check `claude-usage-tracker` is on PATH: `which claude-usage-tracker` |

### Why no API key?

Uses your authenticated browser session (libsecret-decrypted cookies), same approach as the macOS app. API-key auth is out of scope for v1.

### Disclaimer

Same as macOS — calls an undocumented internal endpoint. Anthropic could change or block it at any time.

---

## License

[MIT](./LICENSE)
