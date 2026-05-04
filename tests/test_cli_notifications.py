"""Tests for notification wiring in render-waybar live mode."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from unittest.mock import patch

import pytest

from claude_usage_tracker.cli import main
from claude_usage_tracker.config import Config, NotificationsConfig
from claude_usage_tracker.live_session import RenderInputs
from claude_usage_tracker.notifier import Notification
from claude_usage_tracker.render import RenderError, TranscriptBreakdowns
from claude_usage_tracker.state import NotificationDedupeWindow, State
from claude_usage_tracker.sync import SyncAuthority, SyncedUsage

_ASSEMBLE_RENDER_INPUTS = "claude_usage_tracker.live_session.assemble_render_inputs"
_LOAD_CONFIG = "claude_usage_tracker.config.load_config"
_LOAD_STATE = "claude_usage_tracker.state.load_state"
_DECIDE_NOTIFICATIONS = "claude_usage_tracker.notifier.decide_notifications"
_DISPATCH = "claude_usage_tracker.notifier.dispatch"
_SAVE_STATE = "claude_usage_tracker.state.save_state"


def _make_fresh_sync(percent5h: int = 80) -> SyncedUsage:
    return SyncedUsage(
        percent5h=percent5h,
        percent7d=61,
        reset5h_at=None,
        reset7d_at=None,
        synced_at=datetime.now(UTC),
        authority=SyncAuthority.FRESH,
    )


def _make_stale_sync() -> SyncedUsage:
    return SyncedUsage(
        percent5h=80,
        percent7d=61,
        reset5h_at=None,
        reset7d_at=None,
        synced_at=datetime.now(UTC),
        authority=SyncAuthority.STALE,
    )


def _make_inputs(sync: SyncedUsage | None = None, error: RenderError | None = None) -> RenderInputs:
    return RenderInputs(
        sync=sync or _make_fresh_sync(),
        breakdowns=TranscriptBreakdowns(top_model=None, top_project=None),
        error=error,
    )


def _mock_notification() -> Notification:
    return Notification(
        kind="block",
        threshold=75,
        title="Claude usage: 80% of 5h block",
        body="5h usage at 80%",
        urgency="normal",
    )


def test_first_crossing_fires_once(capsys: pytest.CaptureFixture[str]):
    """First threshold crossing fires notify-send exactly once."""
    empty_state = State()
    new_state = State(
        notification_dedupe={"key": NotificationDedupeWindow(window_id="key", sent_thresholds=[75])}
    )
    notification = _mock_notification()

    with (
        patch(_ASSEMBLE_RENDER_INPUTS, return_value=_make_inputs()),
        patch(_LOAD_STATE, return_value=empty_state),
        patch(_DECIDE_NOTIFICATIONS, return_value=([notification], new_state)),
        patch(_DISPATCH) as mock_dispatch,
        patch(_SAVE_STATE) as mock_save,
    ):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "class" in payload
    mock_dispatch.assert_called_once_with(notification)
    mock_save.assert_called_once_with(new_state)


def test_dedupe_no_refire(capsys: pytest.CaptureFixture[str]):
    """Second poll within same window does not refire."""
    already_sent_state = State(
        notification_dedupe={"key": NotificationDedupeWindow(window_id="key", sent_thresholds=[75])}
    )

    with (
        patch(_ASSEMBLE_RENDER_INPUTS, return_value=_make_inputs()),
        patch(_LOAD_STATE, return_value=already_sent_state),
        patch(_DECIDE_NOTIFICATIONS, return_value=([], already_sent_state)),
        patch(_DISPATCH) as mock_dispatch,
        patch(_SAVE_STATE) as mock_save,
    ):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "class" in payload
    mock_dispatch.assert_not_called()
    mock_save.assert_not_called()


def test_stale_no_fire(capsys: pytest.CaptureFixture[str]):
    """Stale sync never fires notifications."""
    stale_inputs = _make_inputs(sync=_make_stale_sync())

    with (
        patch(_ASSEMBLE_RENDER_INPUTS, return_value=stale_inputs),
        patch(_DECIDE_NOTIFICATIONS) as mock_decide,
    ):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "class" in payload
    mock_decide.assert_not_called()


def test_notifications_disabled_no_fire(capsys: pytest.CaptureFixture[str]):
    """Disabled notifications skip threshold evaluation entirely."""
    disabled_config = Config(notifications=NotificationsConfig(enabled=False))

    with (
        patch(_LOAD_CONFIG, return_value=disabled_config),
        patch(_ASSEMBLE_RENDER_INPUTS, return_value=_make_inputs()),
        patch(_DECIDE_NOTIFICATIONS) as mock_decide,
    ):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "class" in payload
    mock_decide.assert_not_called()


def test_dispatch_failure_swallowed(capsys: pytest.CaptureFixture[str]):
    """Dispatch failure does not crash CLI; valid JSON still emitted."""
    empty_state = State()
    new_state = State(
        notification_dedupe={"key": NotificationDedupeWindow(window_id="key", sent_thresholds=[75])}
    )
    notification = _mock_notification()

    with (
        patch(_ASSEMBLE_RENDER_INPUTS, return_value=_make_inputs()),
        patch(_LOAD_STATE, return_value=empty_state),
        patch(_DECIDE_NOTIFICATIONS, return_value=([notification], new_state)),
        patch(_DISPATCH, side_effect=RuntimeError("notify-send not found")),
        patch(_SAVE_STATE) as mock_save,
    ):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "class" in payload
    assert "notify: dispatch failed:" in captured.err
    mock_save.assert_called_once_with(new_state)
