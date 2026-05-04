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

### [2026-05-04] Notifier
- Notification dedupe must key off reset-window ISO timestamps, not raw fixture strings; normalize fixture `Z` timestamps to `+00:00` in tests.
- `decide_notifications()` should stay pure and return the updated `State` only when notifications actually fire.
- `notify-send` dispatch should stay list-form and fire-and-forget; stderr logging is enough for failures.

### [2026-05-04] Live Session Orchestrator
- `RenderInputs` frozen dataclass: `sync`, `breakdowns`, `error` fields — same pattern as other domain dataclasses
- secretstorage exceptions caught by `type(exc).__name__` string matching — avoids import dependency while portable
- `_compute_breakdowns` uses `sync.reset5h_at - 5h` as block start (reset marks END of block), falls back to `now - 5h`
- Block filter: `entry.timestamp >= block_start` (entries exactly at block start are included)
- Breakdown format: `f"{row.label} {int(row.share * 100)}%"` — truncates (not rounds) share percent
- Test pattern: `monkeypatch.setattr(live_session, "resolve_profile", ...)` patches imported names in module namespace
- Fake secretstorage exception classes: plain subclasses of `Exception` with correct class `__name__` trigger the type-name dispatch
- Git identity needs env vars `GIT_AUTHOR_NAME/EMAIL` + `GIT_COMMITTER_NAME/EMAIL` when git config is absent
- ruff I001 (isort): `--fix` auto-resolves; stdlib imports must precede third-party

### [2026-05-04] System Path Resolvers
- `default_browser_root()` should return `Path.home() / ".config"` and stay pathlib-only.
- `default_transcript_root()` should return `Path.home() / ".claude" / "projects"` for local transcript scans.
- `secret_service_status()` is diagnostic-only: no decryption, just import/dbus/service/lookups with graceful failure snapshots.
- Tests can mock `secretstorage` directly via `sys.modules`; file-level pyright suppression is useful for MagicMock-heavy test isolation.

### [2026-05-04] Live Mode CLI Wiring
- `_handle_render_waybar` is now live-mode-by-default: `fixture_suite=None` triggers real orchestration, `fixture_suite` provided triggers fixture passthrough
- Mock target for `assemble_render_inputs` in tests must be `"claude_usage_tracker.live_session.assemble_render_inputs"` (where it's defined, not where it's imported)
- Fixture files updated: `\r` for tooltip line breaks, string class (not array), simplified tooltips for error states
- Internal exceptions in live mode: catch-all writes traceback to stderr, emits `{"text": "—", "tooltip": "Internal error: <ExcType>", "class": "error"}`, returns 0
- `--fixture-suite` and `--config` are both `required=False, default=None` in argparse for render-waybar
- `getattr(args, "fixture_suite", None)` pattern handles attribute presence safely
- Live mode HTTP 403 = no active session in this environment; emits valid JSON with `"class": "error usage-none"`, exit 0 ✓

### [2026-05-04] Doctor Live Mode
- `doctor` now defaults to live diagnostics when `--fixture-suite` is omitted.
- Live doctor output reports `secret_service_status()` plus `resolve_profile(default_browser_root(), config_path=None)` and transcript count from `~/.claude/projects`.
- Fixture doctor path still reads `manifest.json` unchanged when `--fixture-suite` is provided.
- Exit status stays `0` for `ok`/`warn` and `1` for `fail`.
