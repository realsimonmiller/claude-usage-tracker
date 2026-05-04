"""CLI command contracts for the Linux rewrite."""

import json
import os
import subprocess
import sys
from pathlib import Path

FIXTURES = Path("tests/fixtures")
CONFIG = FIXTURES / "configs" / "default.toml"


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = "src"
    return subprocess.run(
        [sys.executable, "-m", "claude_usage_tracker", *args],
        capture_output=True,
        text=True,
        env=env,
    )


def test_render_waybar_live_suite_emits_waybar_json_contract():
    result = run_cli(
        "render-waybar",
        "--fixture-suite",
        "tests/fixtures/render/live_ok",
        "--config",
        str(CONFIG),
    )

    assert result.returncode == 0, result.stderr
    assert result.stderr == ""

    payload = json.loads(result.stdout)
    assert set(payload) == {"class", "percentage", "text", "tooltip"}
    assert isinstance(payload["text"], str)
    assert payload["text"].strip()
    assert payload["text"] == "42%"
    assert isinstance(payload["percentage"], int)
    assert payload["percentage"] == 42
    assert isinstance(payload["class"], str)
    assert payload["class"] == "fresh usage-medium"
    assert isinstance(payload["tooltip"], str)
    assert payload["tooltip"] == (
        "5h usage: 42%\r"
        "Weekly usage: 61%\r"
        "Top model: Sonnet 58%\r"
        "Top project: cli-redesign 31%"
    )
    assert "\n" not in payload["tooltip"]
    assert "<" not in payload["tooltip"]


def test_render_waybar_missing_session_suite_still_emits_non_empty_text():
    result = run_cli(
        "render-waybar",
        "--fixture-suite",
        "tests/fixtures/render/missing_session",
        "--config",
        str(CONFIG),
    )

    assert result.returncode == 0, result.stderr
    assert result.stderr == ""

    payload = json.loads(result.stdout)
    assert payload["text"] == "—"
    assert isinstance(payload["class"], str)
    assert payload["class"] == "missing-session usage-none"
    assert payload["tooltip"] == "No browser session found"


def test_doctor_success_suite_reports_supported_browser_profile_and_backend():
    result = run_cli(
        "doctor",
        "--fixture-suite",
        "tests/fixtures/browser_catalog/chrome_default",
        "--config",
        str(CONFIG),
    )

    assert result.returncode == 0, result.stderr
    assert result.stderr == ""
    assert result.stdout == (
        "status: ok\n"
        "browser: chrome\n"
        "profile: Default\n"
        "backend: secret-service\n"
    )


def test_doctor_failure_suite_uses_stderr_for_clear_failure_reason():
    result = run_cli(
        "doctor",
        "--fixture-suite",
        "tests/fixtures/browser_catalog/missing_cookies",
        "--config",
        str(CONFIG),
    )

    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == (
        "doctor: no supported browser profile contains a Cookies database\n"
    )


def test_settings_headless_save_copies_canonical_config(tmp_path: Path):
    save_path = tmp_path / "saved.toml"

    result = run_cli(
        "settings",
        "--config",
        str(CONFIG),
        "--headless-save",
        str(save_path),
    )

    assert result.returncode == 0, result.stderr
    assert result.stderr == ""
    assert result.stdout == f"saved settings to {save_path}\n"
    assert save_path.read_text(encoding="utf-8") == CONFIG.read_text(encoding="utf-8")
