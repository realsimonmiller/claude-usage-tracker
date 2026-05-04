"""Waybar JSON renderer for usage state."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from claude_usage_tracker.sync import SyncAuthority, SyncedUsage


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
        return f"{sync.percent5h}%"
    return "—"


def _tooltip(
    *,
    sync: SyncedUsage | None,
    breakdowns: TranscriptBreakdowns | None,
    error: RenderError | None,
) -> str:
    if sync is not None and sync.authority is SyncAuthority.FRESH and error is None:
        lines = [f"5h usage: {sync.percent5h}%", f"Weekly usage: {sync.percent7d}%"]
        if breakdowns is not None:
            if breakdowns.top_model:
                lines.append(f"Top model: {breakdowns.top_model}")
            if breakdowns.top_project:
                lines.append(f"Top project: {breakdowns.top_project}")
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
