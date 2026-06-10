# AgentBar repo notes

This repo is the source of truth for AgentBar. A fresh agent should be able to clone it, run `./scripts/install.sh`, and get a working menu-bar app.

## Install / reload

Run:

```bash
./scripts/install.sh
```

This builds `AgentBar.app`, installs `agent-watch`, writes the LaunchAgent, and reloads `com.max.agentbar`.

## Validate

```bash
make build-only
make status
~/.local/bin/agent-watch list
~/.local/bin/agent-watch json | jq .
```

The app bundle is installed to `/opt/homebrew/Applications/AgentBar.app` by default. Keep this path unless the user asks otherwise; local app paths were unreliable on this Mac.

## Editing

- App source: `AgentBar.swift`
- Engine: `agent-watch`
- Installer: `scripts/install.sh`
- LaunchAgent template/source: `com.max.agentbar.plist`

After changing Swift or the engine, run `make build-only` first. If that succeeds, run `make install` to reload the live app.

## Contribution checklist

- Keep generated app bundles, logs, and caches out of git.
- Verify `agent-watch json` is valid JSON.
- Verify LaunchAgent is running after install.
- Document user-visible shortcuts, install paths, or behavior changes in `README.md`.
