"""Tests for the live session orchestrator."""

from __future__ import annotations

import importlib
from datetime import UTC, datetime
from pathlib import Path

import pytest

live_session = importlib.import_module("claude_usage_tracker.live_session")
assemble_render_inputs = live_session.assemble_render_inputs
RenderInputs = live_session.RenderInputs

sync_mod = importlib.import_module("claude_usage_tracker.sync")
SyncedUsage = sync_mod.SyncedUsage
SyncAuthority = sync_mod.SyncAuthority
MissingSessionCookieError = sync_mod.MissingSessionCookieError
MissingOrgCookieError = sync_mod.MissingOrgCookieError
SyncHTTPStatusError = sync_mod.SyncHTTPStatusError

ProfileResolutionError = importlib.import_module(
    "claude_usage_tracker.browser.profiles"
).ProfileResolutionError

RenderError = importlib.import_module("claude_usage_tracker.render").RenderError
Config = importlib.import_module("claude_usage_tracker.config").Config
UsageEntry = importlib.import_module("claude_usage_tracker.domain.models").UsageEntry


# Fake secretstorage exception types — named to match secretstorage's class names
class LockedException(Exception):
    pass


class PromptDismissedException(Exception):
    pass


class ItemNotFoundException(Exception):
    pass


NOW = datetime(2026, 5, 4, 12, 0, tzinfo=UTC)
FAKE_SYNC = SyncedUsage(
    percent5h=42,
    percent7d=61,
    reset5h_at=datetime(2026, 5, 4, 14, 0, tzinfo=UTC),
    reset7d_at=datetime(2026, 5, 9, 0, 0, tzinfo=UTC),
    synced_at=NOW,
    authority=SyncAuthority.FRESH,
)
FAKE_ENTRY = UsageEntry.from_usage(
    timestamp="2026-05-04T10:00:00Z",
    model="claude-3-5-sonnet",
    project="/home/user/my-project",
    input_tokens=100,
    output_tokens=10,
)


def _call(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    *,
    resolve_side_effect: Exception | None = None,
    fetch_side_effect: Exception | None = None,
    fetch_return: object = FAKE_SYNC,
    load_return: list | None = None,
) -> "RenderInputs":
    def fake_resolve(*args, **kwargs):
        if resolve_side_effect is not None:
            raise resolve_side_effect
        return object()

    def fake_fetch(*args, **kwargs):
        if fetch_side_effect is not None:
            raise fetch_side_effect
        return fetch_return

    def fake_load(*args, **kwargs):
        return load_return if load_return is not None else []

    monkeypatch.setattr(live_session, "resolve_profile", fake_resolve)
    monkeypatch.setattr(live_session, "fetch_live_usage", fake_fetch)
    monkeypatch.setattr(live_session, "load_entries", fake_load)

    return assemble_render_inputs(
        config=Config(),
        transcript_root=tmp_path,
        browser_root=tmp_path,
        now=NOW,
    )


def test_profile_resolution_error_maps_to_missing_session(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, resolve_side_effect=ProfileResolutionError("no browser"))

    assert result.error is RenderError.MISSING_SESSION
    assert result.sync is None
    assert result.breakdowns is None


def test_missing_session_cookie_maps_to_missing_session(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_side_effect=MissingSessionCookieError())

    assert result.error is RenderError.MISSING_SESSION
    assert result.sync is None
    assert result.breakdowns is None


def test_missing_org_cookie_maps_to_missing_org(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_side_effect=MissingOrgCookieError())

    assert result.error is RenderError.MISSING_ORG
    assert result.sync is None
    assert result.breakdowns is None


def test_http_403_maps_to_http_forbidden(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_side_effect=SyncHTTPStatusError(403))

    assert result.error is RenderError.HTTP_FORBIDDEN
    assert result.sync is None
    assert result.breakdowns is None


def test_http_500_maps_to_http_other(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_side_effect=SyncHTTPStatusError(500))

    assert result.error is RenderError.HTTP_OTHER
    assert result.sync is None
    assert result.breakdowns is None


def test_keyring_locked_maps_correctly(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_side_effect=LockedException("ring locked"))

    assert result.error is RenderError.KEYRING_LOCKED
    assert result.sync is None
    assert result.breakdowns is None


def test_prompt_dismissed_maps_correctly(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_side_effect=PromptDismissedException("dismissed"))

    assert result.error is RenderError.KEYRING_UNLOCK_DISMISSED
    assert result.sync is None
    assert result.breakdowns is None


def test_prompt_dismissed_distinct_from_locked(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    dismissed_result = _call(
        monkeypatch, tmp_path, fetch_side_effect=PromptDismissedException("dismissed")
    )
    locked_result = _call(
        monkeypatch, tmp_path, fetch_side_effect=LockedException("locked")
    )

    assert dismissed_result.error is RenderError.KEYRING_UNLOCK_DISMISSED
    assert locked_result.error is RenderError.KEYRING_LOCKED
    assert dismissed_result.error is not locked_result.error


def test_happy_path_returns_sync_and_breakdowns(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_return=FAKE_SYNC, load_return=[FAKE_ENTRY])

    assert result.error is None
    assert result.sync is FAKE_SYNC
    assert result.breakdowns is not None
    assert result.breakdowns.top_model == "sonnet 100%"
    assert result.breakdowns.top_project == "my-project 100%"


def test_empty_transcripts_returns_none_breakdowns(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_return=FAKE_SYNC, load_return=[])

    assert result.error is None
    assert result.sync is FAKE_SYNC
    assert result.breakdowns is not None
    assert result.breakdowns.top_model is None
    assert result.breakdowns.top_project is None


def test_item_not_found_maps_to_keyring_key_not_found(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    result = _call(monkeypatch, tmp_path, fetch_side_effect=ItemNotFoundException("key missing"))

    assert result.error is RenderError.KEYRING_KEY_NOT_FOUND
    assert result.sync is None
    assert result.breakdowns is None
