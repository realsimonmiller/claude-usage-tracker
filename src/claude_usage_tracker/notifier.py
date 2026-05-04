# pyright: reportMissingTypeStubs=false
"""Threshold-based desktop notifications for synced Claude usage."""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime

from claude_usage_tracker.config import Config
from claude_usage_tracker.state import NotificationDedupeWindow, State
from claude_usage_tracker.sync import SyncAuthority, SyncedUsage


@dataclass(frozen=True, slots=True)
class Notification:
    kind: str
    threshold: int
    title: str
    body: str
    urgency: str


def decide_notifications(
    *,
    sync: SyncedUsage,
    config: Config,
    state: State,
    now: datetime,
) -> tuple[list[Notification], State]:
    """Decide which notifications should fire and return the updated state."""

    if sync.authority is not SyncAuthority.FRESH:
        return [], state

    notifications: list[Notification] = []
    notification_dedupe = dict(state.notification_dedupe)

    block_window_id = sync.reset5h_at.isoformat() if sync.reset5h_at else sync.synced_at.isoformat()
    block_window = notification_dedupe.get(
        block_window_id,
        NotificationDedupeWindow(window_id=block_window_id),
    )
    block_sent = set(block_window.sent_thresholds)
    for threshold in config.notifications.block_thresholds:
        if sync.percent5h < threshold or threshold in block_sent:
            continue
        notifications.append(
            Notification(
                kind="block",
                threshold=threshold,
                title=f"Claude usage: {sync.percent5h}% of 5h block",
                body=(
                    f"Resets in {_countdown(sync.reset5h_at, now)}"
                    if sync.reset5h_at is not None
                    else f"5h usage at {sync.percent5h}%"
                ),
                urgency=_urgency_for_threshold(threshold),
            )
        )
        block_sent.add(threshold)

    if block_sent:
        notification_dedupe[block_window_id] = NotificationDedupeWindow(
            window_id=block_window_id,
            sent_thresholds=sorted(block_sent),
        )

    week_window_id = sync.reset7d_at.isoformat() if sync.reset7d_at else sync.synced_at.isoformat()
    week_window = notification_dedupe.get(
        week_window_id,
        NotificationDedupeWindow(window_id=week_window_id),
    )
    week_sent = set(week_window.sent_thresholds)
    for threshold in config.notifications.week_thresholds:
        if sync.percent7d < threshold or threshold in week_sent:
            continue
        notifications.append(
            Notification(
                kind="week",
                threshold=threshold,
                title=f"Claude usage: {sync.percent7d}% of weekly limit",
                body=(
                    f"Resets in {_countdown(sync.reset7d_at, now)}"
                    if sync.reset7d_at is not None
                    else f"Weekly usage at {sync.percent7d}%"
                ),
                urgency=_urgency_for_threshold(threshold),
            )
        )
        week_sent.add(threshold)

    if week_sent:
        notification_dedupe[week_window_id] = NotificationDedupeWindow(
            window_id=week_window_id,
            sent_thresholds=sorted(week_sent),
        )

    if notifications:
        return notifications, State(notification_dedupe=notification_dedupe)
    return [], state


def dispatch(notification: Notification) -> None:
    """Send a desktop notification via notify-send."""

    try:
        _ = subprocess.run(
            [
                "notify-send",
                "--app-name=claude-usage-tracker",
                f"--urgency={notification.urgency}",
                notification.title,
                notification.body,
            ],
            check=False,
            timeout=2,
        )
    except subprocess.TimeoutExpired as exc:
        _ = sys.stderr.write(f"notifier: dispatch failed: {exc}\n")
    except Exception as exc:  # pragma: no cover - defensive logging
        _ = sys.stderr.write(f"notifier: dispatch failed: {exc}\n")


def _countdown(reset_at: datetime, now: datetime) -> str:
    if reset_at <= now:
        return "soon"

    total_minutes = int((reset_at - now).total_seconds() // 60)
    hours, minutes = divmod(total_minutes, 60)
    if hours:
        return f"{hours}h {minutes}m" if minutes else f"{hours}h"
    return f"{minutes}m"


def _urgency_for_threshold(threshold: int) -> str:
    if threshold < 75:
        return "low"
    if threshold < 90:
        return "normal"
    return "critical"
