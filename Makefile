# --- macOS appearance watcher (watchers/macos) ---

WATCHER_DIR    := watchers/macos
WATCHER_LABEL  := com.github.alberti42.zac-watch-macos
WATCHER_BIN    := $(WATCHER_DIR)/.build/release/zac-watch-macos
WATCHER_PLIST_IN := $(WATCHER_DIR)/launchd/$(WATCHER_LABEL).plist.in

# Override on the command line, e.g.
#   make watcher-install IO_CMD=$$HOME/bin/my-io-script
PREFIX      ?= $(HOME)/.local
DISPATCH_BIN ?= $(CURDIR)/bin/appearance-dispatch
IO_CMD      ?=
AGENT_PATH   ?= /opt/homebrew/bin:/usr/local/bin:$(HOME)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
LOG_DIR     ?= $(HOME)/Library/Logs
PLIST_DEST   := $(HOME)/Library/LaunchAgents/$(WATCHER_LABEL).plist

.PHONY: bump-version watcher watcher-install watcher-uninstall watcher-status watcher-clean

watcher:
	cd $(WATCHER_DIR) && swift build -c release

watcher-install: watcher
	install -d $(PREFIX)/bin $(LOG_DIR)
	install -m 755 $(WATCHER_BIN) $(PREFIX)/bin/zac-watch-macos
	sed -e 's|@WATCHER_BIN@|$(PREFIX)/bin/zac-watch-macos|g' \
	    -e 's|@DISPATCH_BIN@|$(DISPATCH_BIN)|g' \
	    -e 's|@IO_CMD@|$(IO_CMD)|g' \
	    -e 's|@PATH@|$(AGENT_PATH)|g' \
	    -e 's|@LOG_DIR@|$(LOG_DIR)|g' \
	    $(WATCHER_PLIST_IN) > $(PLIST_DEST)
	@# Reload: bootout first so an updated plist is picked up.
	-launchctl bootout gui/$$(id -u)/$(WATCHER_LABEL) 2>/dev/null
	launchctl bootstrap gui/$$(id -u) $(PLIST_DEST)
	@printf 'installed %s\nlog: %s/zac-watch-macos.log\n' "$(PLIST_DEST)" "$(LOG_DIR)"

watcher-uninstall:
	-launchctl bootout gui/$$(id -u)/$(WATCHER_LABEL) 2>/dev/null
	rm -f $(PLIST_DEST) $(PREFIX)/bin/zac-watch-macos

watcher-status:
	launchctl print gui/$$(id -u)/$(WATCHER_LABEL) | head -20

watcher-clean:
	rm -rf $(WATCHER_DIR)/.build

bump-version:
ifndef VERSION
	$(error VERSION is not set. Usage: make bump-version VERSION=x.y.z)
endif
	@# Update Version: header in the Emacs module
	sed 's/^;; Version: .*$$/;; Version: $(VERSION)/' \
		editors/emacs/zac-theme-autodetection.el \
		> editors/emacs/zac-theme-autodetection.el.tmp
	mv editors/emacs/zac-theme-autodetection.el.tmp \
		editors/emacs/zac-theme-autodetection.el
	@# Update Version: header in the tmux catppuccin theme
	sed 's/^# Version: .*$$/# Version: $(VERSION)/' \
		examples/tmux/catppuccin.conf \
		> examples/tmux/catppuccin.conf.tmp
	mv examples/tmux/catppuccin.conf.tmp \
		examples/tmux/catppuccin.conf
	@# Update the version in the macOS watcher (header comment + constant)
	sed -e 's|^// Version: .*$$|// Version: $(VERSION)|' \
		-e 's|^let zacWatchVersion = ".*"$$|let zacWatchVersion = "$(VERSION)"|' \
		$(WATCHER_DIR)/Sources/zac-watch-macos/main.swift \
		> $(WATCHER_DIR)/Sources/zac-watch-macos/main.swift.tmp
	mv $(WATCHER_DIR)/Sources/zac-watch-macos/main.swift.tmp \
		$(WATCHER_DIR)/Sources/zac-watch-macos/main.swift
	@# Promote the [Unreleased] section of CHANGELOG.md to this version.
	@# Fails when [Unreleased] is empty, so a release always has notes.
	zsh -f bin/changelog release $(VERSION)
	@# Commit the release edits first, so the tag points at them and not at the
	@# previous commit.
	git commit -m "chore: release v$(VERSION)" \
		CHANGELOG.md \
		editors/emacs/zac-theme-autodetection.el \
		examples/tmux/catppuccin.conf \
		$(WATCHER_DIR)/Sources/zac-watch-macos/main.swift
	@# Create local git tag
	git tag v$(VERSION)
