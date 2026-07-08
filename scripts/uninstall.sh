#!/usr/bin/env bash
set -euo pipefail

if command -v codex-headless >/dev/null 2>&1; then
  codex-headless off || true
fi

if [[ -e /usr/local/bin/codex-headless ]]; then
  if [[ -w /usr/local/bin ]]; then
    rm -f /usr/local/bin/codex-headless
  else
    sudo rm -f /usr/local/bin/codex-headless
  fi
fi

if [[ -e /Applications/CodexHeadless.app ]]; then
  if [[ -w /Applications ]]; then
    rm -rf /Applications/CodexHeadless.app
  else
    sudo rm -rf /Applications/CodexHeadless.app
  fi
fi

rm -f "$HOME/Library/LaunchAgents/com.codexheadless.app.plist"

echo "Removed CodexHeadless CLI, app bundle, and LaunchAgent. Logs and config were preserved."
