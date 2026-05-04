from __future__ import annotations

import sys
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

from claude_usage_tracker.browser.profiles import ProfileResolutionError, resolve_profile
from claude_usage_tracker.config import Config
from claude_usage_tracker.domain.aggregation import model_breakdown, project_breakdown
from claude_usage_tracker.domain.models import UsageEntry
from claude_usage_tracker.domain.transcripts import load_entries
from claude_usage_tracker.render import RenderError, TranscriptBreakdowns
from claude_usage_tracker.sync import (
    MissingOrgCookieError,
    MissingSessionCookieError,
    SyncedUsage,
    SyncHTTPStatusError,
    fetch_live_usage,
)


@dataclass(frozen=True, slots=True)
class RenderInputs:
    sync: SyncedUsage | None
    breakdowns: TranscriptBreakdowns | None
    error: RenderError | None


def assemble_render_inputs(
    *,
    config: Config,
    transcript_root: Path,
    browser_root: Path,
    now: datetime | None = None,
) -> RenderInputs:
    try:
        profile = resolve_profile(browser_root, config_path=None)
    except ProfileResolutionError:
        return RenderInputs(sync=None, breakdowns=None, error=RenderError.MISSING_SESSION)

    try:
        sync = fetch_live_usage(profile)
    except MissingSessionCookieError:
        return RenderInputs(sync=None, breakdowns=None, error=RenderError.MISSING_SESSION)
    except MissingOrgCookieError:
        return RenderInputs(sync=None, breakdowns=None, error=RenderError.MISSING_ORG)
    except SyncHTTPStatusError as exc:
        if exc.status_code == 403:
            return RenderInputs(sync=None, breakdowns=None, error=RenderError.HTTP_FORBIDDEN)
        return RenderInputs(sync=None, breakdowns=None, error=RenderError.HTTP_OTHER)
    except Exception as exc:
        exc_type = type(exc).__name__
        if exc_type == "PromptDismissedException":
            return RenderInputs(
                sync=None, breakdowns=None, error=RenderError.KEYRING_UNLOCK_DISMISSED
            )
        if exc_type == "LockedException":
            return RenderInputs(sync=None, breakdowns=None, error=RenderError.KEYRING_LOCKED)
        if exc_type == "ItemNotFoundException":
            return RenderInputs(
                sync=None, breakdowns=None, error=RenderError.KEYRING_KEY_NOT_FOUND
            )
        sys.stderr.write(f"live_session: unexpected error: {type(exc).__name__}: {exc}\n")
        return RenderInputs(sync=None, breakdowns=None, error=RenderError.HTTP_OTHER)

    entries = load_entries(transcript_root)
    effective_now = now if now is not None else datetime.now(UTC)
    breakdowns = _compute_breakdowns(entries, sync, effective_now)
    return RenderInputs(sync=sync, breakdowns=breakdowns, error=None)


def _compute_breakdowns(
    entries: list[UsageEntry],
    sync: SyncedUsage,
    now: datetime,
) -> TranscriptBreakdowns:
    if sync is not None and sync.reset5h_at is not None:
        block_start = sync.reset5h_at - timedelta(hours=5)
    else:
        block_start = now - timedelta(hours=5)

    filtered = [e for e in entries if e.timestamp >= block_start]

    if not filtered:
        return TranscriptBreakdowns(top_model=None, top_project=None)

    model_rows = model_breakdown(filtered)
    project_rows = project_breakdown(filtered)

    top_model = (
        f"{model_rows[0].label} {int(model_rows[0].share * 100)}%" if model_rows else None
    )
    top_project = (
        f"{project_rows[0].label} {int(project_rows[0].share * 100)}%" if project_rows else None
    )

    return TranscriptBreakdowns(top_model=top_model, top_project=top_project)
