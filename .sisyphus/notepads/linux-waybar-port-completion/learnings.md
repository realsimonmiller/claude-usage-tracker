# Learnings — linux-waybar-port-completion

## [2026-05-04] Session Start

### Codebase Patterns
- Frozen dataclasses with `slots=True`: `@dataclass(frozen=True, slots=True)` — used in sync.py, state.py, config.py
- All modules use `from __future__ import annotations`
- Tests use pytest functions (not classes), fixture-based, dataclass-equality assertions
- Commit footer: `Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-openagent)\n\nCo-authored-by: Sisyphus <clio-agent@sisyphuslabs.ai>`

### Key Types
- `SyncedUsage` (sync.py:57-86): frozen dataclass with percent5h, percent7d, reset5h_at, reset7d_at, synced_at, authority
- `SyncAuthority` enum: FRESH="fresh", STALE="stale"
- `State` (state.py): frozen dataclass with notification_dedupe dict
- `NotificationDedupeWindow`: window_id + sent_thresholds list
- `Config` (config.py): browser_mode, profile_override, refresh_interval_seconds, tooltip, notifications, settings_window
- `NotificationsConfig`: enabled, block_thresholds=[50,75,90], week_thresholds=[50,75,90]

### Existing Exceptions (sync.py)
- `MissingSessionCookieError` (SyncError subclass)
- `MissingOrgCookieError` (SyncError subclass)
- `SyncHTTPStatusError(status_code)` (SyncError subclass)
- `SyncParseError` (SyncError subclass)

### Browser
- `ProfileResolutionError` in browser/profiles.py
- `resolve_profile(browser_root, config_path=None)` → ResolvedProfile

### Transcripts
- `load_entries(root)` → list[UsageEntry] in domain/transcripts.py
- `model_breakdown(entries)` → list[BreakdownRow] in domain/aggregation.py
- `project_breakdown(entries, limit=3)` → list[BreakdownRow] in domain/aggregation.py
- BreakdownRow has: label, ncu, share (0.0-1.0), entry_count, family

### Fixture Formats
- Render fixture expected.json currently uses `\n` and array class — MUST be updated to `\r` and string class
- Notification fixture snapshot.json uses camelCase (isFresh, reset5hAt, reset7dAt) — different from SyncedUsage dataclass
- Notification state-before/after uses `{"notifications": {"block": {}, "week": {}}}` — different from State dataclass format

### Waybar Constraints
- `class` MUST always be present (never omit) — Waybar issue #3234
- Tooltip line breaks MUST use `\r` (carriage return), never `\n`
- `percentage` only when authority is FRESH
- No `format` field in waybar config
- Signal 11 is free (7,8,9,10 taken)

### Test Infrastructure
- 45 tests passing (ignoring test_fixture_integrity.py import error)
- Run: `.venv/bin/pytest tests/ --ignore=tests/test_fixture_integrity.py -q`
- Ruff for linting: `.venv/bin/ruff check src/ tests/`

### [2026-05-04] Waybar Renderer
- `render_waybar()` should always emit `text`, `tooltip`, and `class`; `class` is a string, never a list.
- Tooltip line breaks for Waybar must use `\r` only; tests should assert `\n` is absent.
- Fresh syncs include `percentage`; stale/error states do not.
- `RenderError.STALE_SYNC` tooltip is `Sync data is stale`, while stale live data (no error) uses `Stale data`.
