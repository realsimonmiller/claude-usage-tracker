#!/usr/bin/env bash

# Installs claude-usage-tracker on Linux (Arch / Omarchy).
# Idempotent — safe to re-run.
# Usage: bash scripts/install-linux.sh [--dry-run]

set -euo pipefail

[[ "$(uname)" == "Linux" ]] || { echo "This script is for Linux only."; exit 1; }

DRY_RUN="${1:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WAYBAR_CONFIG="${WAYBAR_CONFIG:-$HOME/.config/waybar/config.jsonc}"
WAYBAR_STYLE="${WAYBAR_STYLE:-$HOME/.config/waybar/style.css}"

say() { printf '\e[1;34m==> \e[0m%s\n' "$1"; }

do_or_dry() {
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "DRY: $*"
  else
    eval "$*"
  fi
}

# 1. Ensure uv is available
command -v uv >/dev/null || { echo "uv not installed. Install from https://astral.sh/uv"; exit 1; }

# 2. Install package as a uv tool (puts CLI on PATH)
say "Installing claude-usage-tracker via uv tool"
do_or_dry "uv tool install --from \"$REPO_ROOT\" claude-usage-tracker --reinstall"

# 3. Patch waybar config (only if not already present)
say "Patching $WAYBAR_CONFIG"
if [[ -f "$WAYBAR_CONFIG" ]]; then
  if ! grep -q '"custom/claude-usage"' "$WAYBAR_CONFIG"; then
    do_or_dry "python3 \"$REPO_ROOT/scripts/patch-waybar-config.py\" \"$WAYBAR_CONFIG\" \"$REPO_ROOT/scripts/waybar-snippet.jsonc\""
  else
    echo "  already present, skipping"
  fi
else
  echo "  $WAYBAR_CONFIG not found, skipping"
fi

# 4. Append style rules (only if not already present)
say "Patching $WAYBAR_STYLE"
if [[ -f "$WAYBAR_STYLE" ]]; then
  if ! grep -q '#custom-claude-usage' "$WAYBAR_STYLE"; then
    do_or_dry "cat \"$REPO_ROOT/scripts/waybar-style.css\" >> \"$WAYBAR_STYLE\""
  else
    echo "  already present, skipping"
  fi
else
  echo "  $WAYBAR_STYLE not found, skipping"
fi

# 5. Reload waybar
say "Reloading waybar"
do_or_dry "pkill -SIGUSR2 waybar || true"

say "Done. Run: claude-usage-tracker doctor"
