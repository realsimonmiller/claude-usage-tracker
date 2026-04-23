# Design Doc — claude-usage-tracker

**Status:** Draft v0.2
**Author:** Erik Lissinger
**Last updated:** 2026-04-22

---

## 1. Summary

A macOS menu bar widget that shows real-time Claude Code plan usage against your rolling 5-hour and 7-day caps. The icon is a Doom HUD face that gets visibly bloodier as your remaining quota shrinks — health = budget. Everything runs locally by parsing Claude Code's transcript files.

## 2. Goals

- **Glanceable cap proximity.** A user should know in <1 second whether they're safe, warm, or about to hit the wall.
- **Charming, not nagging.** The Doom face turns a frustrating limit into something fun. No popups, no badges, no notifications by default.
- **Local-only.** No network, no auth, no scraping. Privacy is a feature, not a marketing line.
- **Lightweight.** Idles at <1% CPU and <50MB RAM. Doesn't slow down login or hog the menu bar.
- **Accurate enough.** Within ~5% of `ccusage` for the same window — not a billing system, just a HUD.

## 3. Non-goals (v1)

- Animated faces, idle blinking, "ouch" reactions, sound effects → v2.
- Web `claude.ai` chat usage → no public API, would require fragile session scraping.
- Anthropic API console / Admin API spend tracking → different audience (API users, not Plan subscribers).
- Push notifications when crossing thresholds → easy to add later, not core to the HUD metaphor.
- Multi-machine usage aggregation → assumes one Mac per user.
- Historical charts beyond the active windows → v2.

## 4. Background

Claude Code writes one JSONL file per session at `~/.claude/projects/<sanitized-cwd>/<session-uuid>.jsonl`. Every assistant turn line includes a timestamp, the model used, and a `usage` block:

```json
{
  "type": "assistant",
  "timestamp": "2026-04-22T10:00:00.123Z",
  "message": {
    "model": "claude-opus-4-7",
    "usage": {
      "input_tokens": 6,
      "cache_creation_input_tokens": 33497,
      "cache_read_input_tokens": 0,
      "output_tokens": 385,
      "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 }
    }
  }
}
```

This is enough to reconstruct usage over any time window without touching the network. The community tool [ccusage](https://github.com/ryoppippi/ccusage) does exactly this and is our reference implementation for parsing semantics and plan coefficients.

Anthropic does not publish exact token caps for Pro / Max plans — they publish "approximate message counts." This means our caps are **calibrated heuristics**, not contract values, and must be user-overridable.

## 5. Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                ClaudeUsageTracker.app  (LSUIElement)           │
│                                                                │
│  ┌────────────────┐        ┌────────────────────────────┐     │
│  │ FSEventsWatcher│───────▶│ TranscriptScanner          │     │
│  │  (kernel hook) │        │  - walks ~/.claude/projects│     │
│  └────────────────┘        │  - byte-offset table       │     │
│                            └──────────┬─────────────────┘     │
│                                       │ new JSONL lines       │
│                                       ▼                        │
│                            ┌────────────────────────────┐     │
│                            │ JSONLParser                │     │
│                            │  - stream parse, defensive │     │
│                            │  - emits UsageEntry        │     │
│                            └──────────┬─────────────────┘     │
│                                       ▼                        │
│                            ┌────────────────────────────┐     │
│                            │ UsageAggregator            │     │
│                            │  - in-memory ring buffer   │     │
│                            │  - 5h + 7d sliding sums    │     │
│                            │  - per-model normalization │     │
│                            └──────────┬─────────────────┘     │
│                                       ▼                        │
│                            ┌────────────────────────────┐     │
│                            │ HealthModel                │     │
│                            │  used / cap → bucket 0..5  │     │
│                            └──────────┬─────────────────┘     │
│                                       ▼                        │
│           ┌───────────────────────────┴───────────────┐       │
│           ▼                                           ▼       │
│  ┌─────────────────┐                    ┌─────────────────────┐
│  │ MenuBarView     │                    │ DetailPopover       │
│  │ NSStatusItem    │                    │ SwiftUI             │
│  │ face + % label  │                    │ bars, breakdown     │
│  └─────────────────┘                    └─────────────────────┘
└────────────────────────────────────────────────────────────────┘
```

### Module responsibilities

| Module | Responsibility | Key dependencies |
|---|---|---|
| `FSEventsWatcher` | Subscribe to filesystem events for `~/.claude/projects/`. Debounce bursts. | `FSEventStreamCreate` |
| `TranscriptScanner` | Walk project tree on launch and on FS events. Track per-file byte offsets. Read only new bytes since last offset. | `FileHandle`, `OffsetStore` |
| `JSONLParser` | Parse one JSONL line at a time. Tolerate unknown fields, missing keys, schema drift. Skip non-assistant lines. | `JSONDecoder` with custom keyed strategy |
| `UsageAggregator` | Append-only ring of `UsageEntry`. Drop entries older than 7d. Compute 5h and 7d sums on demand (or maintain incrementally). | — |
| `PlanConfig` | Plan-tier presets (Pro, Max 5×, Max 20×, Custom) → cap values in normalized cost units. Per-model multipliers. | `UserDefaults` for overrides |
| `HealthModel` | Maps `used / cap` to an enum `HealthBucket` (0..5 + special states `dead`, `evilGrin`). | — |
| `MenuBarController` | Owns `NSStatusItem`. Updates icon + optional label on `HealthModel` changes. Wires popover. | `AppKit` |
| `DetailPopover` | SwiftUI view shown on click. Two progress bars (5h, 7d), reset countdowns, model split, top sessions in last 5h. | `SwiftUI` |
| `SettingsView` | Plan picker, custom caps, refresh interval, show/hide label, launch-at-login toggle. | `SMAppService` |
| `OffsetStore` | Persists per-file byte offsets to disk so we don't re-parse on relaunch. | `Codable` JSON file |

## 6. Data model

```swift
struct UsageEntry: Codable {
    let timestamp: Date
    let model: String              // "claude-opus-4-7", "claude-sonnet-4-6", ...
    let inputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
}

enum HealthBucket: Int {
    case healthy        // 0–20%   used
    case scuffed        // 20–50%
    case bruised        // 50–75%
    case bloody         // 75–95%
    case critical       // 95–100%
    case dead           // ≥100%
    case evilGrin       // transient: shown for ~3s after window resets
}

struct PlanConfig {
    let tier: PlanTier              // .pro, .max5x, .max20x, .custom
    let cap5h: Double               // normalized cost units
    let cap7d: Double
    let modelWeights: [String: Double]
}
```

## 7. Normalization & caps

We collapse heterogeneous token types and models into a single scalar — **normalized cost units (NCU)** — that approximates Anthropic's billable cost. This lets us sum across models and turn types into one "budget used" number.

### 7.1 Token-type weights (per million tokens, relative to Sonnet input)

| Token type | Weight |
|---|---|
| `input_tokens` | 1.0 |
| `cache_creation_input_tokens` | 1.25 |
| `cache_read_input_tokens` | 0.10 |
| `output_tokens` | 5.0 |

### 7.2 Model weights (multiplied on top)

| Model family | Weight |
|---|---|
| `claude-opus-*` | 5.0 |
| `claude-sonnet-*` | 1.0 |
| `claude-haiku-*` | 0.25 |
| Unknown | 1.0 (logged) |

### 7.3 Per-entry NCU

```
ncu(entry) = modelWeight(entry.model)
           * ( 1.00 * entry.inputTokens
             + 1.25 * entry.cacheCreationTokens
             + 0.10 * entry.cacheReadTokens
             + 5.00 * entry.outputTokens )
           / 1_000_000
```

### 7.4 Default caps (heuristic — calibrate after dogfooding)

| Plan | 5h cap (NCU) | 7d cap (NCU) |
|---|---|---|
| Pro | 50 | 350 |
| Max 5× | 250 | 1750 |
| Max 20× | 1000 | 7000 |

These are placeholders. We'll refine by:
1. Cross-referencing community-derived numbers from `ccusage`.
2. Recording the user's NCU at the moment they hit a cap (Settings UI: "I just hit my cap, calibrate").
3. Letting users set Custom caps explicitly.

## 8. Rolling window algorithm

Anthropic's actual semantics: a 5h timer starts on the *first* message of a fresh window. The 7d window appears to be a fixed weekly reset. We approximate both as **sliding sums** — simpler and never under-reports.

```swift
func sum(window: TimeInterval, now: Date = .now) -> Double {
    let cutoff = now.addingTimeInterval(-window)
    return entries
        .reversed()                    // entries are append-time-sorted
        .prefix(while: { $0.timestamp >= cutoff })
        .map(ncu)
        .reduce(0, +)
}
```

Complexity: O(k) where k = entries inside the window. With ~100 turns/day a Max user has ~700 entries in a 7d ring — negligible.

**Reset detection:** when 5h sum transitions from >0 to 0, emit `evilGrin` for 3s, then settle to `healthy`.

## 9. File watching & incremental parsing

```
~/.claude/projects/
  └── -Users-eriklissinger-Documents-foo/
        ├── 9028f201-....jsonl   ← active session, grows over time
        └── e1a4b7c2-....jsonl   ← finished session, immutable
```

### Strategy

1. On launch: walk the tree, load `OffsetStore` from `~/Library/Application Support/ClaudeUsageTracker/offsets.json`.
2. For each JSONL file: open with `FileHandle`, seek to stored offset, read to EOF, parse line by line, append to `UsageAggregator`, save new offset.
3. Subscribe to FSEvents on `~/.claude/projects/`. Debounce events with a 500ms trailing window (Claude Code can flush several lines in quick succession).
4. On event: re-scan changed files only (FSEvents gives us paths).
5. Backfill on first launch ever: parse last 7 days of files in full.

### Edge cases

| Case | Handling |
|---|---|
| Truncated last line (write in flight) | Fail-soft: don't advance offset past the partial line; retry on next event. |
| File deleted | Drop offset entry. |
| File renamed | FSEvents emits `kFSEventStreamEventFlagItemRenamed`; treat as delete + new. |
| Clock skew (timestamp in future) | Clamp to `now` for window calc; log warning. |
| Schema drift (new model, new keys) | `JSONDecoder` ignores unknown keys; unknown model gets weight 1.0 + logged. |
| Multiple Claude Code processes writing concurrently | Each writes to its own file; no cross-file coordination needed. |

## 10. UI / UX

### 10.1 Design philosophy

It's a **HUD, not a dashboard.** Glanceable first, browsable second, configurable third. Every interaction should answer "how close am I to the wall?" in under a second. Anything that takes more thought belongs in Settings.

Two visual languages live side by side:

- **Doom HUD aesthetic** for the face itself and the popover's segmented progress bars — chunky pixel art, intentional 1980s-FPS feel. This is the joke and we lean into it.
- **Native macOS chrome** for everything else — system fonts (SF Pro), system materials (`.regularMaterial` blur), rounded corners, dark/light mode-aware colors. We don't fight the OS.

Color is purposeful and restrained. Red means budget burn. Outside the face sprites and the bar fills, we stay neutral.

### 10.2 Menu bar icon

**Anatomy**

```
       ┌──────────────────────┐
       │  ▒ ▒ … ⓘ 🔍  [😐 73%] │   ← icon + optional % label, right-aligned in menu bar
       └──────────────────────┘
                       ↑
                  our status item
```

| Property | Value |
|---|---|
| Icon size | 22 × 22 pt (44 × 44 px @2×) |
| Padding from label | 4 pt |
| Label font | SF Pro Text, 12 pt, monospaced digits, system foreground |
| Label format | `73%` — integer percent of `max(5h%, 7d%)` |
| Status item length | `NSStatusItem.variableLength` |
| Click behavior | Toggle popover |
| Right-click | Show context NSMenu |
| Hover tooltip | `5h: 73% · 7d: 41% · resets in 1h 12m` |

**Visual states**

| State | Trigger | Face | Label | Tooltip suffix |
|---|---|---|---|---|
| `healthy` | 0–20% used | grinning, untouched | `12%` | `you're fine` |
| `scuffed` | 20–50% | small bruise | `34%` | (none) |
| `bruised` | 50–75% | visible damage | `62%` | (none) |
| `bloody` | 75–95% | bloodied | `81%` | `getting tight` |
| `critical` | 95–100% | barely standing | `97%` | `slow down` |
| `dead` | ≥100% (cap hit) | `STFDEAD0` skull | `MAX` | `cap hit · resets in N` |
| `evilGrin` | window just reset | `STFEVL0` | `0%` | `fresh window — go nuts` |
| `noData` | first launch, before backfill | greyscale healthy face | `—` | `gathering data…` |
| `paused` | user paused updates | greyscale healthy face | `‖` | `paused` |
| `error` | can't read JSONL | greyscale healthy face with `?` overlay | `!` | `can't read transcripts — click for details` |

Whichever window (5h or 7d) has the higher used % drives the bucket and the label, so the user always sees their tightest constraint.

### 10.3 Detail popover (left-click)

```
╭──────────────────────────────────────────────╮
│                                              │
│   [face]   Claude Code Usage                 │
│            Max 5×                            │
│                                              │
│   ─────────────────────────────────────────  │
│                                              │
│   5-hour window                              │
│   ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░  73%    │
│   36.2 / 50.0 NCU      resets in 1h 12m      │
│                                              │
│   7-day window                               │
│   ▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  41%    │
│   143 / 350 NCU         resets in 4d 6h      │
│                                              │
│   ─────────────────────────────────────────  │
│                                              │
│   Last 5 hours, by model                     │
│     Opus      ▓▓▓▓▓▓▓▓░░    29.1 NCU         │
│     Sonnet    ▓▓░░░░░░░░     6.4 NCU         │
│     Haiku     ░░░░░░░░░░     0.7 NCU         │
│                                              │
│   Top sessions today                         │
│     casals-s26               18.4 NCU        │
│     claude-usage-tracker      9.8 NCU        │
│     ai-hype-tracker           8.0 NCU        │
│                                              │
│   ─────────────────────────────────────────  │
│   ⚙ Settings…              ⏸ Pause   ⌘Q      │
╰──────────────────────────────────────────────╯
```

**Layout & sizing**

| Property | Value |
|---|---|
| Width | 320 pt |
| Height | adapts to content (~420 pt typical) |
| Material | `.popover` (system blur) |
| Padding | 16 pt all sides |
| Section gap | 16 pt |
| Header face | 32 × 32 pt, the same sprite as the menu bar |
| Bar style | rounded rect, 8 pt tall, segmented look (10 cells) for Doom feel |
| Bar fill color | `systemRed` if % ≥ 75, `systemOrange` 50–75, `systemGreen` <50 |
| Numbers | SF Mono, 13 pt |
| Section headers | SF Pro, 11 pt, semibold, secondary label color, uppercase |
| Footer buttons | borderless `.plain` style, system tinted |

**Component breakdown**

1. **Header** — face sprite (matches menu bar), title `Claude Code Usage`, plan tier subtitle.
2. **Window panels (×2)** — title, segmented bar, raw NCU value, reset countdown. Reset countdown updates live every second when popover is open.
3. **Model breakdown** — last 5h only. Hidden if total = 0.
4. **Top sessions today** — top 3 sessions by NCU since local midnight. Click a row → opens that session's working directory in Finder.
5. **Footer** — Settings, Pause/Resume, Quit (`⌘Q`).

**Interactions**

| Trigger | Result |
|---|---|
| `Esc` | Dismiss popover |
| Click outside | Dismiss popover |
| Click row in "Top sessions" | Reveal that session's `cwd` in Finder |
| Hover a bar | Tooltip with full precision: `36.241 / 50.000 NCU (72.48%)` |
| `⌘,` | Open Settings |
| `⌘R` | Force re-scan |

### 10.4 Right-click menu

```
About claude-usage-tracker
─────────────────────────
Settings…                ⌘,
Force refresh            ⌘R
Pause updates
─────────────────────────
Quit                     ⌘Q
```

When paused: `Pause updates` becomes `Resume updates` and the menu bar icon goes greyscale with a `‖` label.

### 10.5 Settings window

A standalone window (not a sheet on the popover — popover dismisses on focus loss, which makes settings forms maddening). Opens centered, 480 × 360 pt, non-resizable, single tabless pane.

```
╭──────────────────────────────────────────────────╮
│  Settings                                        │
│  ──────────────────────────────────────────────  │
│                                                  │
│   Plan tier        ( • Pro                    )  │
│                    (   Max 5×                  ) │
│                    (   Max 20×                 ) │
│                    (   Custom                  ) │
│                                                  │
│   5-hour cap        [   50.0  ] NCU              │
│   7-day cap         [  350.0  ] NCU              │
│                                                  │
│   Refresh every     ( 5 seconds         ▾   )    │
│                                                  │
│   ☑  Show % label in menu bar                    │
│   ☐  Launch at login                             │
│   ☐  Notify when 5h crosses 80% (v2)             │
│                                                  │
│   ──────────────────────────────────────────     │
│                                                  │
│   Calibration                                    │
│   Hit your cap? Click below to set your caps     │
│   to your current usage levels.                  │
│                                                  │
│   [ Calibrate to current usage ]                 │
│                                                  │
│   ──────────────────────────────────────────     │
│                                                  │
│   About · Reset to defaults             [Done]   │
╰──────────────────────────────────────────────────╯
```

**Behavior**

- 5-hour cap and 7-day cap fields are **read-only when a preset tier is selected**, editable when `Custom`.
- Selecting a preset tier resets the cap fields to that preset's defaults.
- "Calibrate to current usage" sets the tier to `Custom` and fills both caps with the current windowed NCU values, rounded up to the nearest 10. Confirmation alert: *"Set 5h cap to 36.2 → 40 NCU and 7d cap to 143 → 150 NCU?"*
- Settings auto-save on change; no Save button. `Done` just closes the window.
- `Reset to defaults` is a confirmation alert.

### 10.6 First-launch experience

No splash screen, no walkthrough wizard. The app belongs in the menu bar — the first launch is the same as any other.

1. App launches, lands in menu bar with the `noData` state (greyscale face, `—` label, tooltip: *"gathering data…"*).
2. Backfill runs in the background (<2s for 7 days of data on a typical machine).
3. As soon as we have any data, face transitions to the appropriate live state.
4. **No Settings prompt by default.** The user can discover Settings via right-click. Default plan tier (`Max 5×`) is wrong for many users — but the "Calibrate" button in Settings makes recovery trivial.

If we ever ship via Mac App Store: a one-time onboarding sheet on first launch with a plan-tier picker. Out of scope for v1 self-distribution.

### 10.7 Empty, error, and edge states

| State | Trigger | Visual |
|---|---|---|
| **No data yet** | First launch, backfill in progress, or no Claude Code transcripts on disk | Greyscale face, `—` label. Popover says *"No usage in the last 7 days. Use Claude Code and this'll fill in."* |
| **Permission denied** | macOS sandbox / TCC blocks reading `~/.claude/projects/` | Face with `?` overlay, `!` label. Popover shows *"Can't read your Claude Code transcripts. Grant Full Disk Access in System Settings → Privacy & Security."* with a button that opens that pane via `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. |
| **Parse failures** | Malformed JSONL line | Silent. Logged to `~/Library/Logs/ClaudeUsageTracker.log`. Skip the bad line, keep going. |
| **Cap hit** | 5h or 7d ≥ 100% | Skull face, `MAX` label. Popover shows reset countdown prominently. |
| **Window just reset** | 5h sum drops to 0 after being >0 | Evil grin face for 3 seconds, then settle to `healthy`. `0%` label. |
| **Paused** | User selected Pause | Greyscale face, `‖` label. Popover shows "Paused — click Resume in the menu to continue tracking." |

### 10.8 Animation & motion

Minimal. We're a HUD, not an arcade.

| Moment | Treatment |
|---|---|
| Face bucket change | Instant swap. No crossfade. (Doom didn't crossfade either.) |
| % label tick | No animation; just changes. Monospaced digits prevent jitter. |
| Bar fill in popover | Animate width with `withAnimation(.easeOut(duration: 0.2))` on popover open and on data refresh while open. |
| Popover open/close | System default (`NSPopover` spring). |
| Evil grin transient | 3-second hold, then face transitions to `healthy` instantly. |
| Cap hit | One-shot subtle shake of the menu bar icon (`±2 pt` over 0.3s). Once per cap hit, never repeated until window resets. **Respects "Reduce motion" — no shake when that's on.** |

### 10.9 Accessibility

- **VoiceOver** — status item exposes accessibility label like *"Claude usage 73 percent, bloodied"* (bucket name + percent). Popover elements are individually labeled.
- **Reduce Motion** — disables the cap-hit shake and the evil-grin transient (cuts straight to healthy).
- **Increase Contrast** — bar fills switch to higher-contrast colors; face sprites get a 1px outline.
- **Color blindness** — never rely on red alone. Bar style (segment count visibly filled) and face state both convey severity. Label text always present.
- **Keyboard nav** — popover supports `Tab` between bars and footer buttons; `Esc` dismisses.

### 10.10 Dark / Light mode

Both supported via system `NSAppearance`. Face sprites are full color and identical in both modes (Doomguy doesn't change with the OS theme). Backgrounds, dividers, secondary text all use system semantic colors so they adapt automatically. The popover uses `.popover` material which already does the right thing.

### 10.11 Typography & spacing reference

| Token | Value |
|---|---|
| Title (popover header) | SF Pro Text, 14 pt, semibold |
| Section header | SF Pro Text, 11 pt, semibold, uppercase, secondary color |
| Body | SF Pro Text, 13 pt |
| Numbers | SF Mono, 13 pt |
| Menu bar label | SF Pro Text, 12 pt, monospaced digits |
| Padding (popover) | 16 pt |
| Section gap | 16 pt |
| Inline gap | 8 pt |
| Bar height | 8 pt |
| Corner radius | 6 pt (bars), 10 pt (popover) |

### 10.12 Microcopy reference

Centralized so we keep voice consistent. Voice: dry, terse, slightly amused. Never cute, never alarmist.

| Context | Copy |
|---|---|
| App name | `claude-usage-tracker` |
| Popover title | `Claude Code Usage` |
| Window labels | `5-hour window`, `7-day window` |
| Reset countdown | `resets in 1h 12m` (auto-formatted: seconds → minutes → hours → days) |
| No data | `No usage in the last 7 days. Use Claude Code and this'll fill in.` |
| Permission denied | `Can't read your Claude Code transcripts. Grant Full Disk Access in System Settings.` |
| Permission button | `Open System Settings` |
| Cap hit tooltip | `cap hit · resets in 47m` |
| Healthy tooltip | `you're fine` |
| Bloody tooltip | `getting tight` |
| Critical tooltip | `slow down` |
| Evil grin tooltip | `fresh window — go nuts` |
| Calibrate button | `Calibrate to current usage` |
| Calibrate confirm | `Set 5h cap to {x} NCU and 7d cap to {y} NCU?` |
| Pause menu item | `Pause updates` / `Resume updates` |
| About credits | `Face sprites from Freedoom (BSD). Doomguy is in the public domain spirit.` |

We avoid jargon in user-facing copy: no "JSONL", no "FSEvents", no "ring buffer". `NCU` *is* exposed because it's the user's budget number — but we should consider showing it as just `units` or hiding the value in favor of `%` only. Open question, see §15.

## 11. Settings

| Setting | Default | Notes |
|---|---|---|
| Plan tier | Max 5× | Pro / Max 5× / Max 20× / Custom |
| 5h cap (NCU) | per tier | Editable when tier = Custom |
| 7d cap (NCU) | per tier | Editable when tier = Custom |
| Refresh interval | 5s | 1s / 5s / 15s / 60s |
| Show % label | on | Hide for icon-only |
| Launch at login | off | `SMAppService.mainApp.register()` |
| Calibrate to current usage | button | Sets cap = current 5h/7d sum × 1.0 |

Persisted in `UserDefaults` under suite `com.eriklissinger.ClaudeUsageTracker`.

## 12. Persistence

```
~/Library/Application Support/ClaudeUsageTracker/
  ├── offsets.json     # { "/path/to/session.jsonl": 12345, ... }
  └── settings.plist   # mirrors UserDefaults; backup convenience
```

`UsageEntry` ring is **not** persisted in v1 — we recompute from JSONL on launch (cheap, <1s for 7d of data). Persistence comes if startup time becomes a problem.

## 13. Performance budget

| Metric | Target |
|---|---|
| Idle CPU | <1% |
| Idle memory (RSS) | <50 MB |
| Cold start to first menu bar render | <500 ms |
| Refresh latency (file write → face update) | <1 s |
| 7-day backfill on first launch | <2 s |

## 14. Testing strategy

| Layer | Approach |
|---|---|
| `JSONLParser` | Unit tests with golden fixtures of real JSONL lines. Test schema drift (extra keys, missing optional keys, unknown model). |
| `UsageAggregator` | Unit tests for sliding sum correctness around boundaries; clock-skew clamping. |
| `HealthModel` | Snapshot test: bucket boundaries at 19.9%, 20%, 20.1%, etc. |
| `OffsetStore` | Round-trip tests; corruption handling (malformed JSON → reset offsets, full re-scan). |
| End-to-end | Manual: send messages in a real Claude Code session, watch face update within 1s. |
| Cap behavior | Manual: set cap to 1 NCU in Settings, verify face progresses through all buckets to dead, then resets to evil grin. |
| Cross-check | Sum NCU vs `npx ccusage@latest blocks` output for the same window — should be within 5%. |

## 15. Risks & open questions

| Risk | Mitigation |
|---|---|
| Default cap heuristics are wrong → false sense of safety/panic | "Calibrate" button that records current usage as new cap when user hits the wall. Custom tier always available. |
| Anthropic changes JSONL schema | Defensive parsing; CI fixture set; tracker for `ccusage` updates. |
| FSEvents misses writes (rare but documented) | Backstop poll every 60s as a safety net. |
| Multiple Macs / shared work account | Out of scope for v1. Each Mac shows its own usage. |
| Sprite licensing if we ever ship with original Doom faces | Use Freedoom only (BSD); document attribution in About box. |

**Open questions:**

1. Should the % label use NCU-based percent or Anthropic's own message-count semantics? → NCU is more honest; revisit if it confuses users.
2. Should we expose model breakdown in the menu-bar tooltip, or only in the popover? → Popover only for v1; tooltip is too cramped.
3. How do we handle interactive Plan-mode messages that don't consume cap? → They still appear in the JSONL with `usage`; trust the data.
4. Should the icon be template-rendered (auto monochrome with menu bar tinting) or full color? → **Full color** — we want the blood. Template rendering would defeat the joke.

## 16. Milestones

| ID | Deliverable | Definition of done |
|---|---|---|
| M1 | Static face demo | Xcode project scaffolded; menu bar shows hardcoded face; manual face-bucket switcher in debug menu. |
| M2 | Standalone parser CLI | Swift command-line tool computes 5h/7d NCU from local JSONL; output matches `ccusage` within 5%. |
| M3 | Live aggregation | App reads JSONL on launch + FSEvents updates; face changes in real time as you use Claude Code. |
| M4 | Detail popover | Click icon → SwiftUI popover with both progress bars, reset countdowns, model split. |
| M5 | Settings + persistence | Plan picker, custom caps, launch-at-login, offset persistence across relaunches. |
| M6 | Notarized release | Codesigned, notarized `.dmg` distributable; clean Gatekeeper launch on a fresh user account. |

## 17. Out of scope (future work parking lot)

- Animated faces (idle blink, "ouch" reactions, evil grin idle)
- Optional Doom sound effects on threshold crossings
- Notification when crossing 80% / 95%
- Historical usage chart (last 30 days)
- Multi-machine sync via iCloud
- Web `claude.ai` support if Anthropic ever exposes a usage endpoint
- Linux / Windows ports (`tauri` rewrite if ever)

## 18. References

- [ccusage](https://github.com/ryoppippi/ccusage) — canonical local parser; reference for NCU semantics
- [Freedoom](https://freedoom.github.io/) — BSD-licensed Doom face sprites
- Apple [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice) for login-item registration
- Apple [`NSStatusItem`](https://developer.apple.com/documentation/appkit/nsstatusitem) menu bar integration
- Apple [FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/)
