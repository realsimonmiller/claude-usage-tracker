"""Tests for the live-mode doctor CLI path."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

from claude_usage_tracker.cli import main
from claude_usage_tracker.system import SecretServiceStatus


def _ok_status() -> SecretServiceStatus:
    return SecretServiceStatus(
        available=True,
        available_reason="ok",
        label_lookup_ok=True,
        label_lookup_detail="found 1 item(s)",
        application_lookup_ok=False,
        application_lookup_detail="no items found",
    )


def _unavailable_status() -> SecretServiceStatus:
    return SecretServiceStatus(
        available=False,
        available_reason="service not available",
        label_lookup_ok=False,
        label_lookup_detail="service unavailable",
        application_lookup_ok=False,
        application_lookup_detail="service unavailable",
    )


def test_live_doctor_ok_status(capsys):
    """Live doctor reports ok when profile resolved and secret service available."""

    mock_profile = MagicMock()
    mock_profile.browser_id = "chrome"
    mock_profile.profile_name = "Default"

    with (
        patch("claude_usage_tracker.browser.profiles.resolve_profile", return_value=mock_profile),
        patch("claude_usage_tracker.system.secret_service_status", return_value=_ok_status()),
    ):
        rc = main(["doctor"])

    assert rc == 0
    captured = capsys.readouterr()
    assert "status: ok" in captured.out
    assert "browser: chrome" in captured.out
    assert "profile: Default" in captured.out
    assert "backend: secret-service" in captured.out
    assert "secret_service_available: yes" in captured.out
    assert "secret_service_label_lookup: ok" in captured.out
    assert "transcript_root:" in captured.out


def test_live_doctor_warn_when_both_lookups_fail(capsys):
    """Live doctor reports warn when profile resolved but both key lookups fail."""

    mock_profile = MagicMock()
    mock_profile.browser_id = "chrome"
    mock_profile.profile_name = "Default"

    warn_status = SecretServiceStatus(
        available=True,
        available_reason="ok",
        label_lookup_ok=False,
        label_lookup_detail="no items found",
        application_lookup_ok=False,
        application_lookup_detail="no items found",
    )

    with (
        patch("claude_usage_tracker.browser.profiles.resolve_profile", return_value=mock_profile),
        patch("claude_usage_tracker.system.secret_service_status", return_value=warn_status),
    ):
        rc = main(["doctor"])

    assert rc == 0
    captured = capsys.readouterr()
    assert "status: warn" in captured.out


def test_exit_1_on_profile_fail(capsys):
    """Live doctor exits 1 when profile cannot be resolved."""

    from claude_usage_tracker.browser.profiles import ProfileResolutionError

    with (
        patch(
            "claude_usage_tracker.browser.profiles.resolve_profile",
            side_effect=ProfileResolutionError("no browser"),
        ),
        patch("claude_usage_tracker.system.secret_service_status", return_value=_ok_status()),
    ):
        rc = main(["doctor"])

    assert rc == 1
    captured = capsys.readouterr()
    assert "status: fail" in captured.out


def test_exit_1_on_secret_service_unavailable(capsys):
    """Live doctor exits 1 when secret service unavailable."""

    mock_profile = MagicMock()
    mock_profile.browser_id = "chrome"
    mock_profile.profile_name = "Default"

    with (
        patch("claude_usage_tracker.browser.profiles.resolve_profile", return_value=mock_profile),
        patch(
            "claude_usage_tracker.system.secret_service_status",
            return_value=_unavailable_status(),
        ),
    ):
        rc = main(["doctor"])

    assert rc == 1
    captured = capsys.readouterr()
    assert "status: fail" in captured.out


def test_fixture_doctor_still_works(capsys):
    """--fixture-suite mode still reads manifest.json (regression)."""

    with tempfile.TemporaryDirectory() as tmp:
        suite_dir = Path(tmp)
        manifest = {
            "status": "ok",
            "browser": "chrome",
            "profile": "Default",
            "backend": "secret-service",
        }
        (suite_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

        rc = main(["doctor", "--fixture-suite", str(suite_dir)])

    assert rc == 0
    captured = capsys.readouterr()
    assert "status: ok" in captured.out
    assert "browser: chrome" in captured.out
