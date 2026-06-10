# Contributing

AgentBar is intentionally small: one Swift menu-bar app, one bash detection engine, and install scripts. Keep changes surgical and easy to verify on a real Mac.

## Setup

```bash
./scripts/install.sh
```

This builds and signs `AgentBar.app`, installs `agent-watch`, writes the LaunchAgent, and reloads the live app.

## Where to change things

- `AgentBar.swift` — menu-bar UI, notifications, hotkey, app behavior
- `agent-watch` — Claude/Codex/Pi session detection and terminal focus
- `scripts/install.sh` — build/install/reload flow
- `scripts/uninstall.sh` — cleanup flow
- `com.max.agentbar.plist` — LaunchAgent source template

## Development loop

```bash
make build-only
~/.local/bin/agent-watch list
~/.local/bin/agent-watch json | jq .
make install
make status
```

Use `make build-only` first so compile/signing errors are caught before restarting the live LaunchAgent. Use `make install` only after the build and engine checks pass.

## Legacy install cleanup

The installer overwrites the supported app, engine, and LaunchAgent paths. If a tester has an older AgentBar from another path, clean it before validating your change:

```bash
./scripts/uninstall.sh
pkill -x AgentBar 2>/dev/null || true
rm -rf "$HOME/Applications/AgentBar.app"
rm -f "$HOME/Library/LaunchAgents/agentbar.plist"
./scripts/install.sh
```

Only remove `/Applications/AgentBar.app` with `sudo rm -rf` when you have confirmed it is a legacy AgentBar copy.

## Verification checklist

Before pushing or opening a PR:

```bash
make build-only
make status
~/.local/bin/agent-watch json | jq .
git status --short
```

Also manually verify any affected UI behavior:

- menu opens instantly
- session click focuses the correct iTerm2 tab or Ghostty terminal
- `Ctrl+Option+Command+A` cycles sessions
- working sessions show the spinning indicator
- idle sessions show the static filled indicator
- notification + sound still fire on working -> idle transitions if notification code changed

## Contribution rules

- Do not commit generated app bundles, logs, caches, or local build artifacts.
- Do not shell out from menu rendering; the menu must render from cached state only.
- Keep `agent-watch json` fast and valid JSON.
- Preserve the documented Claude/Codex/Pi detection semantics unless the behavior change is explicit.
- Document user-visible shortcuts, install paths, or behavior changes in `README.md`.
