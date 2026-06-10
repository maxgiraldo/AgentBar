.PHONY: install build-only no-launch uninstall status doctor

install:
	./scripts/install.sh

build-only:
	./scripts/install.sh --build-only

no-launch:
	./scripts/install.sh --no-launch

uninstall:
	./scripts/uninstall.sh

status:
	launchctl print gui/$$(id -u)/com.max.agentbar | grep -E '^\s*(state|pid|runs|last exit) =' || true
	~/.local/bin/agent-watch list || true

doctor:
	command -v jq
	/usr/bin/env -i HOME="$$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcrun --find swiftc
	codesign --verify --deep --strict /opt/homebrew/Applications/AgentBar.app
