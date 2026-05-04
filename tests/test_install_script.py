"""Tests for scripts/install-linux.sh and scripts/patch-waybar-config.py."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"
INSTALL_SCRIPT = SCRIPTS_DIR / "install-linux.sh"
PATCH_SCRIPT = SCRIPTS_DIR / "patch-waybar-config.py"
SNIPPET = SCRIPTS_DIR / "waybar-snippet.jsonc"
STYLE_SNIPPET = SCRIPTS_DIR / "waybar-style.css"


def test_install_script_exists_and_is_executable():
    assert INSTALL_SCRIPT.is_file()
    assert INSTALL_SCRIPT.stat().st_mode & 0o111


def test_install_script_syntax_check():
    result = subprocess.run(
        ["bash", "-n", str(INSTALL_SCRIPT)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"bash -n failed: {result.stderr}"


def test_install_script_dry_run(tmp_path: Path):
    """--dry-run prints DRY: lines and exits 0 without modifying anything."""
    fake_config = tmp_path / "config.jsonc"
    fake_style = tmp_path / "style.css"
    _ = fake_config.write_text('{"modules-right": ["bluetooth"]}', encoding="utf-8")
    _ = fake_style.write_text("/* existing styles */\n", encoding="utf-8")

    env = os.environ.copy()
    env.update({"WAYBAR_CONFIG": str(fake_config), "WAYBAR_STYLE": str(fake_style)})

    result = subprocess.run(
        ["bash", str(INSTALL_SCRIPT), "--dry-run"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, f"dry-run failed: {result.stderr}"
    assert "DRY:" in result.stdout


def test_patch_script_is_idempotent(tmp_path: Path):
    """Running patch-waybar-config.py twice produces same result."""
    config = tmp_path / "config.jsonc"
    _ = config.write_text('{\n  "modules-right": [\n    "bluetooth"\n  ]\n}\n', encoding="utf-8")

    result1 = subprocess.run(
        [sys.executable, str(PATCH_SCRIPT), str(config), str(SNIPPET)],
        capture_output=True,
        text=True,
    )
    assert result1.returncode == 0, f"First patch failed: {result1.stderr}"
    content_after_first = config.read_text(encoding="utf-8")

    result2 = subprocess.run(
        [sys.executable, str(PATCH_SCRIPT), str(config), str(SNIPPET)],
        capture_output=True,
        text=True,
    )
    assert result2.returncode == 0, f"Second patch failed: {result2.stderr}"
    content_after_second = config.read_text(encoding="utf-8")

    assert content_after_first == content_after_second
    assert '"custom/claude-usage"' in content_after_first


def test_waybar_snippet_exists():
    assert SNIPPET.is_file()
    assert STYLE_SNIPPET.is_file()
