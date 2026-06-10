#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATH_VALUE="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$PATH_VALUE"

APP_DIR=${AGENTBAR_APP_DIR:-/opt/homebrew/Applications/AgentBar.app}
APP_BIN="$APP_DIR/Contents/MacOS/AgentBar"
ENGINE_DIR=${AGENTBAR_ENGINE_DIR:-$HOME/.local/bin}
ENGINE_BIN="$ENGINE_DIR/agent-watch"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.max.agentbar.plist"
LOG_DIR="$HOME/.cache/agent-watch"
BUNDLE_ID="com.max.agentbar"

usage() {
  cat <<USAGE
Usage: scripts/install.sh [--build-only] [--no-launch]

Builds and installs AgentBar for the current macOS user.

Environment overrides:
  AGENTBAR_APP_DIR     App bundle path (default: /opt/homebrew/Applications/AgentBar.app)
  AGENTBAR_ENGINE_DIR  agent-watch install dir (default: ~/.local/bin)
USAGE
}

BUILD_ONLY=0
NO_LAUNCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --build-only) BUILD_ONLY=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    return 1
  fi
}

if [ "$(uname -s)" != "Darwin" ]; then
  echo "AgentBar only supports macOS." >&2
  exit 1
fi

need jq || {
  echo "Install jq first: brew install jq" >&2
  exit 1
}
need xcrun
need codesign
need plutil
need launchctl

if ! /usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcrun --find swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ENGINE_DIR" "$(dirname "$LAUNCH_AGENT")" "$LOG_DIR"

install -m 0755 "$ROOT/agent-watch" "$ENGINE_BIN"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AgentBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.max.agentbar</string>
  <key>CFBundleName</key>
  <string>AgentBar</string>
  <key>CFBundleDisplayName</key>
  <string>AgentBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  xcrun swiftc -O -target arm64-apple-macos13.0 \
  "$ROOT/AgentBar.swift" \
  -o "$APP_BIN" \
  -framework AppKit \
  -framework Carbon \
  -framework UserNotifications

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$PATH_VALUE</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/agentbar.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/agentbar.err.log</string>
</dict>
</plist>
PLIST
plutil -lint "$LAUNCH_AGENT" >/dev/null

if [ "$BUILD_ONLY" -eq 1 ]; then
  echo "Built AgentBar.app and installed agent-watch. Skipped LaunchAgent load (--build-only)."
  echo "App: $APP_DIR"
  echo "Engine: $ENGINE_BIN"
  echo "LaunchAgent: $LAUNCH_AGENT"
  exit 0
fi

if [ "$NO_LAUNCH" -eq 1 ]; then
  echo "Installed AgentBar files. Skipped LaunchAgent load (--no-launch)."
  echo "Run: launchctl bootstrap gui/\$(id -u) $LAUNCH_AGENT"
  exit 0
fi

UID_NUM=$(id -u)
if launchctl print "gui/$UID_NUM/$BUNDLE_ID" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$UID_NUM/$BUNDLE_ID"
else
  launchctl bootout "gui/$UID_NUM" "$LAUNCH_AGENT" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_AGENT"
  launchctl kickstart -k "gui/$UID_NUM/$BUNDLE_ID"
fi
sleep 1

launchctl print "gui/$UID_NUM/$BUNDLE_ID" | grep -E '^\s*(state|pid|runs|last exit) =' || true

echo "Installed AgentBar."
echo "App: $APP_DIR"
echo "Engine: $ENGINE_BIN"
echo "LaunchAgent: $LAUNCH_AGENT"
echo "Logs: $LOG_DIR"
echo "Shortcut: Ctrl+Option+Command+A"
