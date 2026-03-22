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
	@# Create release notes skeleton if not already present
	@if [ ! -f release-notes/release-v$(VERSION).md ]; then \
		printf '# Change log\n\n## New features\n\n- \n\n## Bug fixes\n\n- \n' \
			> release-notes/release-v$(VERSION).md; \
		echo "Created release-notes/release-v$(VERSION).md"; \
	else \
		echo "release-notes/release-v$(VERSION).md already exists, skipping"; \
	fi
	@# Create local git tag
	git tag v$(VERSION)
