# Tests

```zsh
make watcher-macos   # macOS only: the watcher tests need the built binary
make test            # or: zsh -f tests/run [-v] [test-file...]
```

The tests cover the plugin, `bin/appearance-dispatch` and both watchers. Each test runs in its own temporary directory with its own `ZAC_CACHE_DIR`, and your `ZAC_*` variables are unset first, so a run never touches your real setup.

## Linux watcher

The Linux watcher is tested through its `custom` backend, and through its portal and `gsettings` backends with fake `gdbus` and `gsettings` commands (`tests/watcher-linux/fakes/`), so those tests need no desktop and also run on macOS.

`tests/watcher-linux/desktop.zsh` checks the watcher against a real D-Bus, dconf, `gsettings` and `xdg-desktop-portal`; it changes the desktop colour scheme, so it runs only with `REAL_DESKTOP_TESTS=1`, in a throwaway session such as the separate Linux CI job.

## macOS watcher

On macOS, one test posts the system's appearance-change notification; an installed `zac-watch-macos` sees it, finds the appearance unchanged, and skips.

`tests/watcher-macos/appearance.zsh` changes the appearance, through `defaults` and through System Events, and checks that the watcher dispatches the new value; it runs only with `REAL_APPEARANCE_TESTS=1`, which the macOS CI job sets.

## CI

CI runs them on Ubuntu and macOS (`.github/workflows/tests-linux.yml`, `.github/workflows/tests-macos.yml`). A third workflow, `.github/workflows/verify-watcher.yml`, downloads the `zac-watch-macos` of the latest release and checks its signature and notarization; it runs when a release is published and every Monday.
