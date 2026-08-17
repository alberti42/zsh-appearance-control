.PHONY: bump-version

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
	@# Promote the [Unreleased] section of CHANGELOG.md to this version.
	@# Fails when [Unreleased] is empty, so a release always has notes.
	zsh -f bin/changelog release $(VERSION)
	@# Commit the release edits first, so the tag points at them and not at the
	@# previous commit.
	git commit -m "chore: release v$(VERSION)" \
		CHANGELOG.md \
		editors/emacs/zac-theme-autodetection.el \
		examples/tmux/catppuccin.conf
	@# Create local git tag
	git tag v$(VERSION)
