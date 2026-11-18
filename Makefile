LABEL      := local.lock-mute
BIN        := build/lock-mute
INSTALL_DIR := $(HOME)/Library/Application Support/lock-mute
PLIST      := $(HOME)/Library/LaunchAgents/$(LABEL).plist
DOMAIN     := gui/$(shell id -u)

.PHONY: build test install uninstall status clean

build: $(BIN)

$(BIN): main.swift
	@mkdir -p build
	swiftc -O -o $@ main.swift

# Starts a temporary daemon and simulates lock and unlock events.
# Does not lock the screen. Restores the mute state.
test: $(BIN)
	./test.sh $(BIN)

install: $(BIN)
	@mkdir -p "$(INSTALL_DIR)" "$(dir $(PLIST))"
	install -m 755 $(BIN) "$(INSTALL_DIR)/lock-mute"
	sed 's|@BIN@|$(INSTALL_DIR)/lock-mute|' $(LABEL).plist.in > "$(PLIST)"
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	launchctl bootstrap $(DOMAIN) "$(PLIST)"
	@echo "Installed. lock-mute is running and starts at each login."

uninstall:
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	rm -f "$(PLIST)"
	rm -rf "$(INSTALL_DIR)"
	@echo "Uninstalled."

status:
	@launchctl print $(DOMAIN)/$(LABEL) 2>/dev/null | grep -E '^\s*(state|pid|last exit code) =' || echo "not loaded"

clean:
	rm -rf build
