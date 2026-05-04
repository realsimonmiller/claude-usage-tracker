"""Tests for system path resolvers and diagnostics."""

# pyright: reportUnknownParameterType=false, reportMissingParameterType=false, reportUnknownMemberType=false, reportAny=false, reportUnknownArgumentType=false

from __future__ import annotations

import builtins
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

from claude_usage_tracker.system import (
    default_browser_root,
    default_transcript_root,
    secret_service_status,
)


def test_default_browser_root_returns_home_config(monkeypatch):
    """Browser root should resolve to ~/.config under the current home."""
    monkeypatch.setattr(Path, "home", lambda: Path("/tmp/fakehome"))

    assert default_browser_root() == Path("/tmp/fakehome/.config")


def test_default_transcript_root_returns_home_claude_projects(monkeypatch):
    """Transcript root should resolve to ~/.claude/projects under the current home."""
    monkeypatch.setattr(Path, "home", lambda: Path("/tmp/fakehome"))

    assert default_transcript_root() == Path("/tmp/fakehome/.claude/projects")


def test_secret_service_status_when_secretstorage_not_installed(monkeypatch):
    """Missing secretstorage should produce a diagnostic unavailable status."""
    real_import = builtins.__import__

    def fake_import(name, globals=None, locals=None, fromlist=(), level=0):
        if name == "secretstorage":
            raise ImportError("secretstorage not installed")
        return real_import(name, globals, locals, fromlist, level)

    monkeypatch.setattr(builtins, "__import__", fake_import)

    status = secret_service_status()

    assert status.available is False
    assert "not installed" in status.available_reason
    assert status.label_lookup_ok is False
    assert status.application_lookup_ok is False


def test_secret_service_status_when_dbus_fails():
    """dbus init failures should be reported as unavailable."""
    mock_secretstorage = MagicMock()
    mock_secretstorage.dbus_init.side_effect = Exception("dbus failed")

    with patch.dict(sys.modules, {"secretstorage": mock_secretstorage}):
        status = secret_service_status()

    assert status.available is False
    assert "dbus_init failed" in status.available_reason


def test_secret_service_status_when_service_unavailable():
    """Service unavailability should return a negative diagnostic."""
    mock_conn = MagicMock()
    mock_secretstorage = MagicMock(
        dbus_init=MagicMock(return_value=mock_conn),
        check_service_availability=MagicMock(return_value=False),
        search_items=MagicMock(),
    )

    with patch.dict(sys.modules, {"secretstorage": mock_secretstorage}):
        status = secret_service_status()

    assert status.available is False
    assert status.available_reason == "service not available"
    assert status.label_lookup_ok is False
    assert status.application_lookup_ok is False


def test_secret_service_status_happy_path_label_found():
    """A found Chrome Safe Storage item should be reported."""
    mock_conn = MagicMock()
    mock_item = MagicMock()
    mock_secretstorage = MagicMock(
        dbus_init=MagicMock(return_value=mock_conn),
        check_service_availability=MagicMock(return_value=True),
        search_items=MagicMock(return_value=[mock_item]),
    )

    with patch.dict(sys.modules, {"secretstorage": mock_secretstorage}):
        status = secret_service_status()

    assert status.available is True
    assert status.label_lookup_ok is True
    assert "found 1 item" in status.label_lookup_detail


def test_secret_service_status_happy_path_no_items():
    """An empty lookup should be reported as no items found."""
    mock_conn = MagicMock()
    mock_secretstorage = MagicMock(
        dbus_init=MagicMock(return_value=mock_conn),
        check_service_availability=MagicMock(return_value=True),
        search_items=MagicMock(return_value=[]),
    )

    with patch.dict(sys.modules, {"secretstorage": mock_secretstorage}):
        status = secret_service_status()

    assert status.available is True
    assert status.label_lookup_ok is False
    assert "no items" in status.label_lookup_detail
    assert status.application_lookup_ok is False
    assert "no items" in status.application_lookup_detail
