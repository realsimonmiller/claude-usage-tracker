"""Tests for Waybar JSON rendering."""

from datetime import UTC, datetime

import pytest

from claude_usage_tracker.render import RenderError, TranscriptBreakdowns, render_waybar
from claude_usage_tracker.sync import SyncAuthority, SyncedUsage


def make_sync(
    percent5h: int,
    *,
    percent7d: int = 61,
    authority: SyncAuthority = SyncAuthority.FRESH,
) -> SyncedUsage:
    return SyncedUsage(
        percent5h=percent5h,
        percent7d=percent7d,
        reset5h_at=None,
        reset7d_at=None,
        synced_at=datetime.now(UTC),
        authority=authority,
    )


@pytest.mark.parametrize(
    ("error", "tooltip", "expected_class"),
    [
        (RenderError.MISSING_SESSION, "No browser session found", "missing-session usage-none"),
        (RenderError.MISSING_ORG, "No organization cookie found", "error usage-none"),
        (RenderError.KEYRING_LOCKED, "Keyring is locked", "error usage-none"),
        (RenderError.KEYRING_UNLOCK_DISMISSED, "Keyring unlock cancelled", "error usage-none"),
        (RenderError.KEYRING_KEY_NOT_FOUND, "Keyring key not found", "error usage-none"),
        (RenderError.HTTP_FORBIDDEN, "Access denied (HTTP 403)", "error usage-none"),
        (RenderError.HTTP_OTHER, "HTTP error", "error usage-none"),
        (RenderError.STALE_SYNC, "Sync data is stale", "error usage-none"),
        (RenderError.NO_TRANSCRIPTS, "No transcripts found", "error usage-none"),
    ],
)
def test_render_errors(error, tooltip, expected_class):
    output = render_waybar(sync=None, breakdowns=None, error=error)

    assert "class" in output
    assert isinstance(output["class"], str)
    assert output["text"] == "—"
    assert output["tooltip"] == tooltip
    assert output["class"] == expected_class
    assert "percentage" not in output


@pytest.mark.parametrize(
    ("percent5h", "expected_tier"),
    [
        (49, "usage-low"),
        (50, "usage-medium"),
        (74, "usage-medium"),
        (75, "usage-high"),
        (89, "usage-high"),
        (90, "usage-critical"),
    ],
)
def test_fresh_sync_tier_boundaries(percent5h, expected_tier):
    output = render_waybar(sync=make_sync(percent5h), breakdowns=None)

    assert "class" in output
    assert isinstance(output["class"], str)
    assert output["class"] == f"fresh {expected_tier}"
    assert output["text"] == f"{percent5h}%"
    assert output["tooltip"] == "5h usage: %s%%\rWeekly usage: 61%%" % percent5h
    assert "\r" in output["tooltip"]
    assert "\n" not in output["tooltip"]
    assert output["percentage"] == percent5h


def test_fresh_sync_with_breakdowns_emits_all_fields():
    output = render_waybar(
        sync=make_sync(42),
        breakdowns=TranscriptBreakdowns(top_model="Sonnet 58%", top_project="cli-redesign 31%"),
    )

    assert "class" in output
    assert isinstance(output["class"], str)
    assert output["text"] == "42%"
    assert output["class"] == "fresh usage-low"
    assert output["percentage"] == 42
    assert output["tooltip"] == (
        "5h usage: 42%\rWeekly usage: 61%\rTop model: Sonnet 58%\r"
        "Top project: cli-redesign 31%"
    )
    assert "\r" in output["tooltip"]
    assert "\n" not in output["tooltip"]


def test_fresh_sync_without_breakdowns_omits_breakdown_lines():
    output = render_waybar(sync=make_sync(42), breakdowns=None)

    assert "class" in output
    assert isinstance(output["class"], str)
    assert output["text"] == "42%"
    assert output["class"] == "fresh usage-low"
    assert output["percentage"] == 42
    assert output["tooltip"] == "5h usage: 42%\rWeekly usage: 61%"
    assert "Top model:" not in output["tooltip"]
    assert "Top project:" not in output["tooltip"]
    assert "\r" in output["tooltip"]
    assert "\n" not in output["tooltip"]


def test_stale_sync_uses_stale_class_and_no_percentage():
    output = render_waybar(sync=make_sync(42, authority=SyncAuthority.STALE), breakdowns=None)

    assert "class" in output
    assert isinstance(output["class"], str)
    assert output["text"] == "—"
    assert output["class"] == "stale usage-none"
    assert output["tooltip"] == "Stale data"
    assert "percentage" not in output


def test_other_error_uses_error_class():
    output = render_waybar(sync=None, breakdowns=None, error=RenderError.MISSING_ORG)

    assert "class" in output
    assert isinstance(output["class"], str)
    assert output["text"] == "—"
    assert output["class"] == "error usage-none"
    assert "error" in output["class"]
    assert output["tooltip"] == "No organization cookie found"
    assert "percentage" not in output
