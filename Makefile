# --- one command per task, whatever the OS ---------------------------------
#
# `make watcher-install` installs the watcher that fits this machine. The
# per-OS targets below still exist for when you want to be explicit, or to
# install for the other launcher.
#
# On Linux there are two launchers, and the choice is not cosmetic: a session
# integrated with `systemd --user` gets the unit, a session that is not (NX,
# xrdp, VNC) gets the XDG autostart entry, because there the unit would never
# start at login and would talk to the wrong D-Bus. That is the same test the
# README describes, so make it rather than ask the reader to make it.
# Override with LINUX_LAUNCHER=systemd|autostart.

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
  WATCHER_OS := macos
else ifeq ($(UNAME_S),Linux)
  WATCHER_OS := linux
  LINUX_LAUNCHER ?= $(shell systemctl --user is-active graphical-session.target 2>/dev/null | grep -qx active && echo systemd || echo autostart)
  ifeq ($(LINUX_LAUNCHER),autostart)
    LINUX_SUFFIX := autostart-
  else
    LINUX_SUFFIX :=
  endif
else
  WATCHER_OS := unsupported
endif

watcher-install watcher-uninstall watcher-status: watcher-%: watcher-$(WATCHER_OS)-$(LINUX_SUFFIX)%
	@:

ifeq ($(WATCHER_OS),unsupported)
watcher-%:
	@echo "no watcher for $(UNAME_S); this project ships one for macOS and one for Linux"; exit 1
endif

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
# The cache directory is a plugin setting, so do not invent a second place to
# configure it: make inherits the environment, so an exported ZAC_CACHE_DIR from
# your shell config lands in the launcher automatically. Empty means "use the
# default", which every consumer resolves the same way (${ZAC_CACHE_DIR:-…}).
CACHE_DIR   ?= $(ZAC_CACHE_DIR)
LOG_DIR     ?= $(HOME)/Library/Logs
PLIST_DEST   := $(HOME)/Library/LaunchAgents/$(WATCHER_LABEL).plist

# --- Linux/GNOME appearance watcher (watchers/linux) ---
#
# A script, so there is nothing to build: install is the only target.
WATCHER_LINUX_DIR  := watchers/linux
WATCHER_LINUX_BIN  := $(WATCHER_LINUX_DIR)/zac-watch-linux
WATCHER_LINUX_UNIT := zac-watch-linux.service
WATCHER_LINUX_UNIT_IN := $(WATCHER_LINUX_DIR)/systemd/$(WATCHER_LINUX_UNIT).in
UNIT_DEST := $(HOME)/.config/systemd/user/$(WATCHER_LINUX_UNIT)
WATCHER_LINUX_DESKTOP_IN := $(WATCHER_LINUX_DIR)/autostart/zac-watch-linux.desktop.in
DESKTOP_DEST := $(HOME)/.config/autostart/zac-watch-linux.desktop
LINUX_PATH ?= $(HOME)/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

.PHONY: bump-version \
	watcher-install watcher-uninstall watcher-status \
	watcher-macos watcher-macos-install watcher-macos-uninstall watcher-macos-status watcher-macos-clean \
	watcher-linux-install watcher-linux-uninstall watcher-linux-status \
	watcher-linux-autostart-install watcher-linux-autostart-uninstall watcher-linux-autostart-status

watcher-macos:
	cd $(WATCHER_DIR) && swift build -c release

watcher-macos-install: watcher-macos
	install -d $(PREFIX)/bin $(LOG_DIR)
	install -m 755 $(WATCHER_BIN) $(PREFIX)/bin/zac-watch-macos
	sed -e 's|@WATCHER_BIN@|$(PREFIX)/bin/zac-watch-macos|g' \
	    -e 's|@DISPATCH_BIN@|$(DISPATCH_BIN)|g' \
	    -e 's|@IO_CMD@|$(IO_CMD)|g' \
	    -e 's|@PATH@|$(AGENT_PATH)|g' \
	    -e 's|@CACHE_DIR@|$(CACHE_DIR)|g' \
	    -e 's|@LOG_DIR@|$(LOG_DIR)|g' \
	    $(WATCHER_PLIST_IN) > $(PLIST_DEST)
	@# Reload: bootout first so an updated plist is picked up.
	-launchctl bootout gui/$$(id -u)/$(WATCHER_LABEL) 2>/dev/null
	launchctl bootstrap gui/$$(id -u) $(PLIST_DEST)
	@printf 'installed %s\nlog: %s/zac-watch-macos.log\n' "$(PLIST_DEST)" "$(LOG_DIR)"
	$(if $(IO_CMD),,@echo "note: installed without IO_CMD. The appearance file and your shells will follow the theme, but config files (tmux, btop, editors, ...) will not. Re-run with IO_CMD=/path/to/your/io-script if you have one.")

watcher-macos-uninstall:
	-launchctl bootout gui/$$(id -u)/$(WATCHER_LABEL) 2>/dev/null
	rm -f $(PLIST_DEST) $(PREFIX)/bin/zac-watch-macos

watcher-macos-status:
	launchctl print gui/$$(id -u)/$(WATCHER_LABEL) | head -20

watcher-macos-clean:
	rm -rf $(WATCHER_DIR)/.build

watcher-linux-install:
	@[ "$$(uname -s)" = Linux ] || { echo "watcher-linux-install: Linux only"; exit 1; }
	install -d $(PREFIX)/bin $(HOME)/.config/systemd/user
	install -m 755 $(WATCHER_LINUX_BIN) $(PREFIX)/bin/zac-watch-linux
	sed -e 's|@WATCHER_BIN@|$(PREFIX)/bin/zac-watch-linux|g' \
	    -e 's|@DISPATCH_BIN@|$(DISPATCH_BIN)|g' \
	    -e 's|@IO_CMD@|$(IO_CMD)|g' \
	    -e 's|@PATH@|$(LINUX_PATH)|g' \
	    -e 's|@CACHE_DIR@|$(CACHE_DIR)|g' \
	    $(WATCHER_LINUX_UNIT_IN) > $(UNIT_DEST)
	systemctl --user daemon-reload
	systemctl --user reenable $(WATCHER_LINUX_UNIT)
	systemctl --user restart $(WATCHER_LINUX_UNIT)
	@printf 'installed %s\nlog: journalctl --user -u %s -f\n' "$(UNIT_DEST)" "$(WATCHER_LINUX_UNIT)"
	$(if $(IO_CMD),,@echo "note: installed without IO_CMD. The appearance file and your shells will follow the theme, but config files (tmux, btop, editors, ...) will not. Re-run with IO_CMD=/path/to/your/io-script if you have one.")

watcher-linux-uninstall:
	-systemctl --user disable --now $(WATCHER_LINUX_UNIT)
	rm -f $(UNIT_DEST) $(PREFIX)/bin/zac-watch-linux
	systemctl --user daemon-reload

watcher-linux-status:
	systemctl --user status $(WATCHER_LINUX_UNIT) --no-pager | head -20

# For a session that is NOT integrated with systemd --user (NX/NoMachine, xrdp,
# VNC): `systemctl --user is-active graphical-session.target` says inactive, and
# the session has its own D-Bus socket in /tmp. The session launches this entry,
# so the watcher inherits the right bus every time, with nothing to import.
watcher-linux-autostart-install:
	@[ "$$(uname -s)" = Linux ] || { echo "watcher-linux-autostart-install: Linux only"; exit 1; }
	install -d $(PREFIX)/bin $(HOME)/.config/autostart
	install -m 755 $(WATCHER_LINUX_BIN) $(PREFIX)/bin/zac-watch-linux
	sed -e 's|@WATCHER_BIN@|$(PREFIX)/bin/zac-watch-linux|g' \
	    -e 's|@DISPATCH_BIN@|$(DISPATCH_BIN)|g' \
	    -e 's|@IO_CMD@|$(IO_CMD)|g' \
	    -e 's|@PATH@|$(LINUX_PATH)|g' \
	    -e 's|@CACHE_DIR@|$(CACHE_DIR)|g' \
	    $(WATCHER_LINUX_DESKTOP_IN) > $(DESKTOP_DEST)
	@printf 'installed %s\nIt starts at your next login. To start it now:\n  env ZAC_DISPATCH=%s ZAC_IO_CMD=%s %s &\n' \
		"$(DESKTOP_DEST)" "$(DISPATCH_BIN)" "$(IO_CMD)" "$(PREFIX)/bin/zac-watch-linux"
	@printf 'If the systemd unit is also installed, remove it: make watcher-linux-uninstall\n'
	$(if $(IO_CMD),,@echo "note: installed without IO_CMD. The appearance file and your shells will follow the theme, but config files (tmux, btop, editors, ...) will not. Re-run with IO_CMD=/path/to/your/io-script if you have one.")

watcher-linux-autostart-uninstall:
	rm -f $(DESKTOP_DEST) $(PREFIX)/bin/zac-watch-linux

# There is no supervisor to ask, so report what exists and what runs.
watcher-linux-autostart-status:
	@test -f $(DESKTOP_DEST) && echo "entry:   $(DESKTOP_DEST)" || echo "entry:   not installed"
	@pgrep -a -u $$(id -u) -f 'zac-watch-linux' || echo "process: not running"

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
	@# Update the version in the Linux watcher (header comment + constant)
	sed -e 's|^# Version: .*$$|# Version: $(VERSION)|' \
		-e 's|^typeset -g VERSION=.*$$|typeset -g VERSION=$(VERSION)|' \
		$(WATCHER_LINUX_BIN) > $(WATCHER_LINUX_BIN).tmp
	mv $(WATCHER_LINUX_BIN).tmp $(WATCHER_LINUX_BIN)
	chmod 755 $(WATCHER_LINUX_BIN)
	@# Promote the [Unreleased] section of CHANGELOG.md to this version.
	@# Fails when [Unreleased] is empty, so a release always has notes.
	zsh -f bin/changelog release $(VERSION)
	@# Commit the release edits first, so the tag points at them and not at the
	@# previous commit.
	git commit -m "chore: release v$(VERSION)" \
		CHANGELOG.md \
		editors/emacs/zac-theme-autodetection.el \
		examples/tmux/catppuccin.conf \
		$(WATCHER_DIR)/Sources/zac-watch-macos/main.swift \
		$(WATCHER_LINUX_BIN)
	@# Create local git tag
	git tag v$(VERSION)
