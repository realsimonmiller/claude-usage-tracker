# pyright: reportMissingTypeStubs=false
"""Tests for threshold-based notify-send notifications."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import cast
from unittest.mock import Mock

import pytest

from claude_usage_tracker.config import Config, NotificationsConfig
from claude_usage_tracker.notifier import Notification, decide_notifications, dispatch
from claude_usage_tracker.state import NotificationDedupeWindow, State
from claude_usage_tracker.sync import SyncAuthority, SyncedUsage

FIXTURES = Path(__file__).parent / "fixtures" / "notifications"


def _read_json(path: Path) -> object:
    return cast(object, json.loads(path.read_text(encoding="utf-8")))


def _sync_from_snapshot(path: Path) -> SyncedUsage:
    payload = cast(dict[str, object], _read_json(path))
    return SyncedUsage(
        percent5h=cast(int, payload["percent5h"]),
        percent7d=cast(int, payload["percent7d"]),
        reset5h_at=_parse_optional_dt(payload.get("reset5hAt")),
        reset7d_at=_parse_optional_dt(payload.get("reset7dAt")),
        synced_at=_parse_dt("2026-05-04T12:00:00Z"),
        authority=(
            SyncAuthority.FRESH
            if cast(bool, payload.get("isFresh", True))
            else SyncAuthority.STALE
        ),
    )


def _state_from_fixture(path: Path) -> State:
    payload = cast(dict[str, object], _read_json(path))
    notifications = cast(dict[str, object], payload["notifications"])

    dedupe: dict[str, NotificationDedupeWindow] = {}
    for kind in ("block", "week"):
        windows = cast(dict[str, list[int]], notifications.get(kind, {}))
        for window_id, thresholds in windows.items():
            normalized_id = _parse_dt(window_id).isoformat()
            dedupe[normalized_id] = NotificationDedupeWindow(
                window_id=normalized_id,
                sent_thresholds=thresholds,
            )
    return State(notification_dedupe=dedupe)


def _parse_dt(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _parse_optional_dt(value: object) -> datetime | None:
    if value is None:
        return None
    assert isinstance(value, str)
    return _parse_dt(value)


def _config(*, block_thresholds: list[int], week_thresholds: list[int]) -> Config:
    return Config(
        notifications=NotificationsConfig(
            enabled=True,
            block_thresholds=block_thresholds,
            week_thresholds=week_thresholds,
        )
    )


def test_no_fire_when_stale():
    sync = SyncedUsage(
        percent5h=99,
        percent7d=99,
        reset5h_at=_parse_dt("2026-05-03T17:00:00Z"),
        reset7d_at=_parse_dt("2026-05-09T00:00:00Z"),
        synced_at=_parse_dt("2026-05-04T12:00:00Z"),
        authority=SyncAuthority.STALE,
    )

    notifications, new_state = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[50], week_thresholds=[50]),
        state=State(),
        now=_parse_dt("2026-05-04T12:00:00Z"),
    )

    assert notifications == []
    assert new_state == State()


def test_no_fire_when_below_threshold():
    sync = SyncedUsage(
        percent5h=49,
        percent7d=49,
        reset5h_at=_parse_dt("2026-05-03T17:00:00Z"),
        reset7d_at=_parse_dt("2026-05-09T00:00:00Z"),
        synced_at=_parse_dt("2026-05-04T12:00:00Z"),
        authority=SyncAuthority.FRESH,
    )

    notifications, new_state = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[50], week_thresholds=[]),
        state=State(),
        now=_parse_dt("2026-05-04T12:00:00Z"),
    )

    assert notifications == []
    assert new_state == State()


def test_block_50_first_fire_matches_fixture():
    sync = _sync_from_snapshot(FIXTURES / "block_50_first_fire" / "snapshot.json")
    state = _state_from_fixture(FIXTURES / "block_50_first_fire" / "state-before.json")

    notifications, new_state = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[50], week_thresholds=[]),
        state=state,
        now=_parse_dt("2026-05-03T16:00:00Z"),
    )

    assert notifications == [
        Notification(
            kind="block",
            threshold=50,
            title="Claude usage: 52% of 5h block",
            body="Resets in 1h",
            urgency="low",
        )
    ]
    assert new_state == State(
        notification_dedupe={
            "2026-05-03T17:00:00+00:00": NotificationDedupeWindow(
                window_id="2026-05-03T17:00:00+00:00",
                sent_thresholds=[50],
            )
        }
    )


def test_block_50_dedupe_matches_fixture():
    sync = _sync_from_snapshot(FIXTURES / "block_50_deduped" / "snapshot.json")
    state = _state_from_fixture(FIXTURES / "block_50_deduped" / "state-before.json")

    notifications, new_state = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[50], week_thresholds=[]),
        state=state,
        now=_parse_dt("2026-05-03T16:00:00Z"),
    )

    assert notifications == []
    assert new_state == state


def test_week_80_first_fire_matches_fixture():
    sync = _sync_from_snapshot(FIXTURES / "week_80_first_fire" / "snapshot.json")
    state = _state_from_fixture(FIXTURES / "week_80_first_fire" / "state-before.json")

    notifications, new_state = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[], week_thresholds=[80]),
        state=state,
        now=_parse_dt("2026-05-08T22:00:00Z"),
    )

    assert notifications == [
        Notification(
            kind="week",
            threshold=80,
            title="Claude usage: 82% of weekly limit",
            body="Resets in 2h",
            urgency="normal",
        )
    ]
    assert new_state == State(
        notification_dedupe={
            "2026-05-09T00:00:00+00:00": NotificationDedupeWindow(
                window_id="2026-05-09T00:00:00+00:00",
                sent_thresholds=[80],
            )
        }
    )


def test_multiple_thresholds_fire_when_stepping_over():
    sync = SyncedUsage(
        percent5h=80,
        percent7d=0,
        reset5h_at=_parse_dt("2026-05-03T17:00:00Z"),
        reset7d_at=None,
        synced_at=_parse_dt("2026-05-04T12:00:00Z"),
        authority=SyncAuthority.FRESH,
    )

    notifications, new_state = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[50, 75], week_thresholds=[]),
        state=State(),
        now=_parse_dt("2026-05-03T16:00:00Z"),
    )

    assert notifications == [
        Notification(
            kind="block",
            threshold=50,
            title="Claude usage: 80% of 5h block",
            body="Resets in 1h",
            urgency="low",
        ),
        Notification(
            kind="block",
            threshold=75,
            title="Claude usage: 80% of 5h block",
            body="Resets in 1h",
            urgency="normal",
        ),
    ]
    assert new_state == State(
        notification_dedupe={
            "2026-05-03T17:00:00+00:00": NotificationDedupeWindow(
                window_id="2026-05-03T17:00:00+00:00",
                sent_thresholds=[50, 75],
            )
        }
    )


def test_window_rollover_clears_thresholds():
    sync = SyncedUsage(
        percent5h=50,
        percent7d=0,
        reset5h_at=_parse_dt("2026-05-04T18:00:00Z"),
        reset7d_at=None,
        synced_at=_parse_dt("2026-05-04T12:00:00Z"),
        authority=SyncAuthority.FRESH,
    )
    state = State(
        notification_dedupe={
            "2026-05-03T17:00:00+00:00": NotificationDedupeWindow(
                window_id="2026-05-03T17:00:00+00:00",
                sent_thresholds=[50],
            )
        }
    )

    notifications, new_state = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[50], week_thresholds=[]),
        state=state,
        now=_parse_dt("2026-05-04T17:00:00Z"),
    )

    assert notifications == [
        Notification(
            kind="block",
            threshold=50,
            title="Claude usage: 50% of 5h block",
            body="Resets in 1h",
            urgency="low",
        )
    ]
    assert new_state == State(
        notification_dedupe={
            "2026-05-03T17:00:00+00:00": NotificationDedupeWindow(
                window_id="2026-05-03T17:00:00+00:00",
                sent_thresholds=[50],
            ),
            "2026-05-04T18:00:00+00:00": NotificationDedupeWindow(
                window_id="2026-05-04T18:00:00+00:00",
                sent_thresholds=[50],
            ),
        }
    )


@pytest.mark.parametrize(
    ("threshold", "urgency"),
    [(49, "low"), (75, "normal"), (90, "critical")],
)
def test_urgency_tiers(threshold: int, urgency: str):
    sync = SyncedUsage(
        percent5h=threshold,
        percent7d=0,
        reset5h_at=_parse_dt("2026-05-03T17:00:00Z"),
        reset7d_at=None,
        synced_at=_parse_dt("2026-05-04T12:00:00Z"),
        authority=SyncAuthority.FRESH,
    )

    notifications, _ = decide_notifications(
        sync=sync,
        config=_config(block_thresholds=[threshold], week_thresholds=[]),
        state=State(),
        now=_parse_dt("2026-05-04T12:00:00Z"),
    )

    assert notifications[0].urgency == urgency


def test_dispatch_uses_list_subprocess(monkeypatch: pytest.MonkeyPatch):
    run = Mock()
    monkeypatch.setattr("claude_usage_tracker.notifier.subprocess.run", run)

    dispatch(
        Notification(
            kind="block",
            threshold=50,
            title="Claude usage: 52% of 5h block",
            body="Resets in 1h",
            urgency="normal",
        )
    )

    run.assert_called_once_with(
        [
            "notify-send",
            "--app-name=claude-usage-tracker",
            "--urgency=normal",
            "Claude usage: 52% of 5h block",
            "Resets in 1h",
        ],
        check=False,
        timeout=2,
    )
