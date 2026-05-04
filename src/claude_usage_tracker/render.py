"""Waybar JSON renderer for usage state."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import Enum

from claude_usage_tracker.sync import SyncAuthority, SyncedUsage

ICON = "󰚩"


class RenderError(str, Enum):
    MISSING_SESSION = "missing-session"
    MISSING_ORG = "missing-org"
    KEYRING_LOCKED = "keyring-locked"
    KEYRING_UNLOCK_DISMISSED = "keyring-unlock-dismissed"
    KEYRING_KEY_NOT_FOUND = "keyring-key-not-found"
    HTTP_FORBIDDEN = "http-forbidden"
    HTTP_OTHER = "http-other"
    STALE_SYNC = "stale-sync"
    NO_TRANSCRIPTS = "no-transcripts"


@dataclass(frozen=True, slots=True)
class TranscriptBreakdowns:
    top_model: str | None
    top_project: str | None


def render_waybar(
    *,
    sync: SyncedUsage | None,
    breakdowns: TranscriptBreakdowns | None,
    error: RenderError | None = None,
) -> dict[str, object]:
    base_class = _base_class(sync=sync, error=error)
    usage_class = _usage_class(sync=sync)
    output: dict[str, object] = {
        "text": _text(sync=sync, error=error),
        "tooltip": _tooltip(sync=sync, breakdowns=breakdowns, error=error),
        "class": f"{base_class} {usage_class}".strip(),
    }
    if sync is not None and sync.authority is SyncAuthority.FRESH:
        output["percentage"] = sync.percent5h
    return output


def _base_class(*, sync: SyncedUsage | None, error: RenderError | None) -> str:
    if error is RenderError.MISSING_SESSION:
        return "missing-session"
    if error is not None:
        return "error"
    if sync is None:
        return "error"
    if sync.authority is SyncAuthority.FRESH:
        return "fresh"
    return "stale"


def _usage_class(*, sync: SyncedUsage | None) -> str:
    if sync is None or sync.authority is not SyncAuthority.FRESH:
        return "usage-none"
    percent = sync.percent5h
    if percent < 50:
        return "usage-low"
    if percent < 75:
        return "usage-medium"
    if percent < 90:
        return "usage-high"
    return "usage-critical"


def _text(*, sync: SyncedUsage | None, error: RenderError | None) -> str:
    if sync is not None and sync.authority is SyncAuthority.FRESH and error is None:
        return f"{ICON} {sync.percent5h}%"
    return f"{ICON} —"


def _tooltip(
    *,
    sync: SyncedUsage | None,
    breakdowns: TranscriptBreakdowns | None,
    error: RenderError | None,
) -> str:
    if sync is not None and sync.authority is SyncAuthority.FRESH and error is None:
        now = datetime.now(UTC)
        lines: list[str] = []

        lines.append("5-HOUR BLOCK")
        block_line = f"{sync.percent5h}%"
        if sync.reset5h_at is not None:
            countdown = _countdown(sync.reset5h_at, now)
            reset_time = sync.reset5h_at.astimezone().strftime("%-I:%M %p")
            block_line += f"  ·  resets in {countdown} · {reset_time}"
        lines.append(block_line)
        lines.append("")

        lines.append("WEEKLY WINDOW")
        week_line = f"{sync.percent7d}%"
        if sync.reset7d_at is not None:
            countdown = _countdown(sync.reset7d_at, now)
            reset_time = sync.reset7d_at.astimezone().strftime("%a %-I:%M %p")
            week_line += f"  ·  resets in {countdown} · {reset_time}"
        lines.append(week_line)

        if breakdowns is not None and breakdowns.top_model:
            lines.append("")
            lines.append("CLAUDE CODE — BY MODEL")
            lines.append(breakdowns.top_model)

        if breakdowns is not None and breakdowns.top_project:
            lines.append("")
            lines.append("CLAUDE CODE — TOP PROJECT")
            lines.append(breakdowns.top_project)

        return "\r".join(lines)

    if error is RenderError.MISSING_SESSION:
        return "No browser session found"
    if error is RenderError.MISSING_ORG:
        return "No organization cookie found"
    if error is RenderError.KEYRING_LOCKED:
        return "Keyring is locked"
    if error is RenderError.KEYRING_UNLOCK_DISMISSED:
        return "Keyring unlock cancelled"
    if error is RenderError.KEYRING_KEY_NOT_FOUND:
        return "Keyring key not found"
    if error is RenderError.HTTP_FORBIDDEN:
        return "Access denied (HTTP 403)"
    if error is RenderError.HTTP_OTHER:
        return "HTTP error"
    if error is RenderError.STALE_SYNC:
        return "Sync data is stale"
    if error is RenderError.NO_TRANSCRIPTS:
        return "No transcripts found"
    if sync is not None and sync.authority is SyncAuthority.STALE:
        return "Stale data"
    return "HTTP error"


def _countdown(reset_at: datetime, now: datetime) -> str:
    if reset_at <= now:
        return "soon"
    total_minutes = int((reset_at - now).total_seconds() // 60)
    hours, minutes = divmod(total_minutes, 60)
    days, hours = divmod(hours, 24)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m" if minutes else f"{hours}h"
    return f"{minutes}m"
