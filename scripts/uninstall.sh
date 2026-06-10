#!/usr/bin/env bash

set -euo pipefail

APP_DIR=${AGENTBAR_APP_DIR:-/opt/homebrew/Applications/AgentBar.app}
ENGINE_DIR=${AGENTBAR_ENGINE_DIR:-$HOME/.local/bin}
ENGINE_BIN="$ENGINE_DIR/agent-watch"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.max.agentbar.plist"
BUNDLE_ID="com.max.agentbar"
UID_NUM=$(id -u)

launchctl bootout "gui/$UID_NUM/$BUNDLE_ID" 2>/dev/null || true
rm -rf "$APP_DIR"
rm -f "$ENGINE_BIN"
rm -f "$LAUNCH_AGENT"

echo "Uninstalled AgentBar. Logs remain at ~/.cache/agent-watch."
