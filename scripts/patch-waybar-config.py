#!/usr/bin/env python3
"""Safely insert the claude-usage module into a Waybar JSONC config.

Usage: python3 patch-waybar-config.py <config.jsonc> <snippet.jsonc>

Backs up original to <config.jsonc>.bak before modifying.
Idempotent: no-op if 'custom/claude-usage' already present.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path
from typing import cast


def strip_jsonc_comments(text: str) -> str:
    """Strip single-line and multi-line comments from JSONC."""
    text = re.sub(r"^\s*//.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return text


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <config.jsonc> <snippet.jsonc>", file=sys.stderr)
        return 1

    config_path = Path(sys.argv[1])
    snippet_path = Path(sys.argv[2])

    if not config_path.is_file():
        print(f"Config not found: {config_path}", file=sys.stderr)
        return 1

    if not snippet_path.is_file():
        print(f"Snippet not found: {snippet_path}", file=sys.stderr)
        return 1

    config_text = config_path.read_text(encoding="utf-8")

    # Idempotence check
    if '"custom/claude-usage"' in config_text:
        print("custom/claude-usage already present, skipping.")
        return 0

    # Parse snippet (strip comments first)
    snippet_clean = strip_jsonc_comments(snippet_path.read_text(encoding="utf-8"))
    snippet_data = cast(dict[str, object], json.loads(snippet_clean))
    module_def = snippet_data.get("custom/claude-usage")
    if module_def is None:
        print("Snippet missing 'custom/claude-usage' key", file=sys.stderr)
        return 1

    # Backup original
    backup_path = config_path.with_suffix(".jsonc.bak")
    _ = shutil.copy2(config_path, backup_path)
    print(f"Backed up to {backup_path}")

    # Insert module reference into modules-right (before "bluetooth")
    new_text = config_text.replace(
        '"bluetooth"',
        '"custom/claude-usage",\n    "bluetooth"',
        1,
    )

    # Insert module definition block (before the closing brace of the config)
    module_json = json.dumps({"custom/claude-usage": module_def}, indent=2)
    # Extract just the inner part (without outer braces)
    inner = module_json.strip()[1:-1].strip()
    # Insert before the last closing brace
    new_text = new_text.rstrip()
    if new_text.endswith("}"):
        new_text = new_text[:-1].rstrip() + ",\n  " + inner + "\n}\n"

    _ = config_path.write_text(new_text, encoding="utf-8")
    print(f"Patched {config_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
