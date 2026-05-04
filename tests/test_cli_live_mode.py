from __future__ import annotations

import json
from datetime import UTC, datetime
from unittest.mock import patch

from claude_usage_tracker.cli import main
from claude_usage_tracker.live_session import RenderInputs
from claude_usage_tracker.render import ICON, RenderError, TranscriptBreakdowns
from claude_usage_tracker.sync import SyncAuthority, SyncedUsage

_PATCH_TARGET = "claude_usage_tracker.live_session.assemble_render_inputs"


def _make_fresh_sync(percent5h: int = 42) -> SyncedUsage:
    return SyncedUsage(
        percent5h=percent5h,
        percent7d=61,
        reset5h_at=None,
        reset7d_at=None,
        synced_at=datetime.now(UTC),
        authority=SyncAuthority.FRESH,
    )


def test_live_mode_emits_valid_waybar_json(capsys):
    mock_inputs = RenderInputs(
        sync=_make_fresh_sync(42),
        breakdowns=TranscriptBreakdowns(top_model="Sonnet 58%", top_project="cli-redesign 31%"),
        error=None,
    )
    with patch(_PATCH_TARGET, return_value=mock_inputs):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "text" in payload
    assert "tooltip" in payload
    assert "class" in payload
    assert isinstance(payload["class"], str)
    assert "fresh" in payload["class"]
    assert "percentage" in payload
    assert payload["percentage"] == 42


def test_live_mode_error_path_emits_error_class(capsys):
    mock_inputs = RenderInputs(sync=None, breakdowns=None, error=RenderError.MISSING_SESSION)
    with patch(_PATCH_TARGET, return_value=mock_inputs):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "class" in payload
    assert "missing-session" in payload["class"]
    assert payload["text"] == f"{ICON} —"


def test_live_mode_internal_exception_still_emits_valid_json_and_exit_0(capsys):
    with patch(_PATCH_TARGET, side_effect=RuntimeError("boom")):
        rc = main(["render-waybar"])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert "class" in payload
    assert payload["text"] == f"{ICON} —"
    assert "RuntimeError" in captured.err


def test_fixture_mode_still_works(tmp_path, capsys):
    fixture_dir = tmp_path / "suite"
    fixture_dir.mkdir()
    expected = {
        "text": "42%",
        "tooltip": "test\rline2",
        "class": "fresh usage-medium",
        "percentage": 42,
    }
    (fixture_dir / "expected.json").write_text(json.dumps(expected))

    rc = main(["render-waybar", "--fixture-suite", str(fixture_dir)])

    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert payload == expected
