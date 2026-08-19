# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Documentation

- The example `zac.zsh` primes the state at load with `_zac.sync` instead of
  `zac sync`. `zac` is a lazy stub, so calling it at startup sources the CLI
  module and defeats the laziness; `_zac.sync` is in `core.zsh` and already
  loaded. Worth about 3 ms per shell.

## [2.2.0] - 2026-08-19

### Added

- **`zac-watch-linux`: a standalone Linux appearance watcher**
  (`watchers/linux/`), a systemd **user** service that watches the desktop
  colour-scheme preference and calls `bin/appearance-dispatch dispatch <0|1>`.
  The counterpart of `zac-watch-macos`, and the same three rules: the D-Bus
  signal is a trigger and the value is always re-read, triggers are debounced
  (`ZAC_WATCH_DEBOUNCE_MS`, default 200 ms) so a burst yields one dispatch, and
  the environment is inherited by the dispatcher rather than parsed.
  - A zsh script, not a compiled binary: nothing to build, nothing to sign, and
    one artifact for every distribution and architecture.
  - Two auto-detected backends: `xdg-desktop-portal`
    (`org.freedesktop.appearance color-scheme`, preferred, works on KDE too) and
    `gsettings monitor org.gnome.desktop.interface color-scheme`. A `custom`
    backend (`ZAC_WATCH_MONITOR_CMD` / `ZAC_WATCH_READ_CMD`) covers an unusual
    desktop, and doubles as the test harness.
  - The dark mapping is the plugin's existing one: `prefer-dark` (portal `1`) is
    dark, `default`, `prefer-light` and portal `0`/`2` are light.
  - Refuses to start without a session D-Bus, instead of running and never
    firing. The unit is bound to `graphical-session.target` for the same reason.
  - Portal calls carry a short timeout (`ZAC_WATCH_PORTAL_TIMEOUT_MS`, default
    3000). `gdbus` waits 25 s by default, and the portal is usually not up yet a
    second after login, when this service starts — which delayed the first
    dispatch by 56 s on a real Ubuntu session before it fell back to gsettings.
  - Detection is retried (`ZAC_WATCH_DETECT_TRIES`, `ZAC_WATCH_DETECT_WAIT_S`)
    when nothing answers, since a session that is still coming up is the usual
    reason; dying instead would eat the unit's start limit during a slow login.
  - Verified on Ubuntu with GNOME: one dispatch per toggle, both backends
    agreeing on the value.
  - Startup warns when the desktop session is on a different D-Bus than the
    watcher, because that combination reads the value correctly and then never
    fires: dconf reads its database file directly and needs no bus, while
    notifications only arrive over the bus. The usual cause is an NX/NoMachine,
    xrdp or VNC session, which runs its own D-Bus daemon.
  - `ZAC_WATCH_VERBOSE=1` logs every line the monitor prints, which is what
    tells "no signal arrives" apart from "the signal is ignored".
  - When its monitor dies (bus or portal restarted) it exits non-zero and lets
    systemd restart it; `StartLimitBurst=5` per minute stops a broken setup from
    spinning. A failed dispatch is retried once, as on macOS.
  - **Requires GNOME 42+ (Ubuntu 22.04+, Fedora 36+) or a desktop whose
    `xdg-desktop-portal` implements `org.freedesktop.appearance`** (KDE Plasma
    5.24+). Older desktops have no preference to watch and are not supported.
- An **XDG autostart entry** (`watchers/linux/autostart/`,
  `make watcher-linux-autostart-install`) as an alternative to the systemd unit,
  for a session that is not integrated with `systemd --user` — where
  `systemctl --user is-active graphical-session.target` says `inactive`. There the
  unit would never start at login, and a unit that is started talks to the wrong
  bus; the session launches the autostart entry itself, so it inherits that
  session's bus and `DISPLAY` by construction, per session. The README says which
  launcher to pick and how to tell.
- `make watcher-linux-install`, `make watcher-linux-status`,
  `make watcher-linux-uninstall`, and `bin/make-watcher-linux`, which packages
  the script, the unit template and the README as `zac-watch-linux-<tag>.zip`.
  Built by the existing Linux job — no new runner. Each release now carries five
  artifacts.
- README: "Option 4: the Linux systemd user service" under *Watcher options*.
- **`examples/dotfiles/`: a complete real-world setup** — the author's own
  `zac.zsh` (zinit load plus an inline callback that stays inside the
  "assignments only" rule), `zac-io-cmd.zsh` (a `ZAC_IO_CMD` themeing a dozen
  tools, treating "not installed here" as a skip rather than an abort) and
  `zac-tmux-cmd.zsh` (the tmux options that live in the server, shared by the io
  script and `tmux.conf`). Snapshots with a header saying what each demonstrates,
  what to replace, and two dated fields: `Snapshot` (when it was copied) and
  `Tested with` (the plugin release it was run against). Not part of any release
  artifact. Linked from the README as *Goodies*.

### Deprecated

- The `tmux` and `cache` sub-commands of `bin/appearance-dispatch`. They are
  still accepted, and they run the same pipeline as `dispatch`, so only the
  spelling differs. The name `tmux` is misleading: since 2.0.0 nothing in this
  project sets a tmux option. Use `dispatch`.

## [2.1.0] - 2026-08-17

### Security

- **The released `zac-watch-macos` binary is signed and notarized.** It is built
  with the hardened runtime and a secure timestamp, signed with a Developer ID
  certificate, and submitted to Apple's notary service by the release workflow.
  An ad-hoc signed binary, which is what a plain `swift build` produces, is
  refused by Gatekeeper once a browser download has set `com.apple.quarantine`,
  and the launch agent then does not start.

  The ticket is not stapled — `stapler` cannot staple a bare Mach-O — so a
  quarantined copy is verified online on first run. A binary you build yourself
  is never quarantined and needs none of this.

### Added

- **`zac-watch-macos`: a standalone macOS appearance watcher** (`watchers/macos/`),
  a small Foundation-only Swift launch agent. It observes
  `AppleInterfaceThemeChangedNotification`, re-reads `AppleInterfaceStyle`, and
  calls `bin/appearance-dispatch dispatch <0|1>`. Terminal-agnostic, so it also
  covers Terminal.app, iTerm2 and Ghostty, and it fires on the automatic sunset
  switch. This closes the "no standalone watcher" gap.
  - Reads one variable of its own, `ZAC_DISPATCH`; everything else
    (`ZAC_IO_CMD`, `ZAC_CACHE_DIR`, `PATH`) is inherited by the dispatcher from
    the launchd plist.
  - Triggers are debounced (`ZAC_WATCH_DEBOUNCE_MS`, default 150 ms) and
    dispatches serialized, so a burst of notifications produces one dispatch.
  - A failed dispatch is retried once (`ZAC_WATCH_RETRY_MS`, default 3000 ms),
    which is safe because a failed dispatch writes nothing and signals nobody.
  - launchd plist template in `watchers/macos/launchd/`, with
    `LimitLoadToSessionType = Aqua` (a background-session job never receives the
    notification).
- `make watcher`, `make watcher-install`, `make watcher-status`,
  `make watcher-uninstall`, `make watcher-clean`.
- `bin/make-watcher`: builds a universal (arm64 + x86_64) release zip, and signs
  the binary when `ZAC_CODESIGN_ID` is set (ad-hoc otherwise, the right default
  for a local build). The release workflow gained a macOS job for it, with
  keychain import, notarization and a smoke test of the signed binary — all
  skipped, not failed, when the signing secrets are absent, so a fork can still
  build the workflow. Each release now carries a fourth artifact,
  `zac-watch-macos-<tag>-macos-universal.zip`.

  A signed release needs four repository secrets: `CERTIFICATE_BASE64`,
  `CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_ID_PASSWORD`.
- README: "Option 3: the macOS launch agent" under *Watcher options*.

## [2.0.0] - 2026-08-17

### Removed

- **The plugin no longer reads the tmux option `@dark_appearance`.** The cache
  file `$ZAC_CACHE_DIR/appearance` is the only ground truth, in tmux and outside
  it, local and remote. `src/platform/tmux.zsh` is deleted.
- **`bin/appearance-dispatch` no longer sets `@dark_appearance`.** tmux is a
  consumer like any other tool. If you theme tmux, set the option from your
  `ZAC_IO_CMD` script:

  ```zsh
  command tmux set-option -gq @dark_appearance "$1" 2>/dev/null
  ```

  Add this to your tmux config as well, because the io script only runs on a real
  transition and a later tmux server would start without the option:

  ```tmux
  run-shell -b 'f="${ZAC_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zac}/appearance"; \
    [ -r "$f" ] && tmux set-option -gq @dark_appearance "$(cat "$f")"'
  ```

- **Shells in tmux panes are no longer signalled by a pane sweep.** Only shells
  in the pid registry receive `USR1`. This removes a real hazard: `USR1`
  terminates a shell that has no handler, so a shell whose plugin had not loaded
  yet was killed. A very young shell may now miss one change; it reads the file
  at load instead.

### Changed

- `ssh-tmux` hands the appearance to the remote host through the file: it runs
  `appearance-dispatch` there, or writes the default remote cache file. It no
  longer sets a tmux option on the remote server.
- The pid registry file now stores the registration time instead of the process
  start time. `appearance-dispatch` accepts a shell whose start time is not later
  than that value, which still rejects a reused PID.

### Added

- Documented tmux hooks as a watcher: `client-dark-theme` and
  `client-light-theme` (tmux 3.6 or newer). tmux detects the theme of the
  attached terminal, which also works for a session attached over ssh.
- `docs/design-tmux-independence.md`: the design direction for per-connection
  appearance over ssh.

### Fixed

- The dispatch lock is stale-proof. A killed dispatch used to leave `io.lock`
  behind, and every later dispatch failed with `failed to acquire lock`. The lock
  records its owner PID, a lock whose owner is dead is stolen, and
  `INT`/`HUP`/`TERM`/`EXIT` release it.
- `src/ssh-tmux.zsh` ended on a failing `compdef` test, so the module loader
  reported a bogus load failure in shells without `compdef`.

### Performance

- Shell startup is about 22 ms faster. `_zac.cache.pid.register` no longer forks
  `mkdir`, `chmod`, `ps` and `date`; it uses `$EPOCHSECONDS` and the `zf_*`
  builtins from `zsh/files`.
- `sync` no longer forks. Reading the ground truth is a builtin read, where the
  old tmux query cost about 6 ms.

## [1.1.0] - 2026-03-22

### Added

- `ZAC_IO_CMD` hook: a single executable path run once per appearance change by
  the dispatcher, before any shell is notified. Intended for heavy I/O such as
  writing tool config files to disk.
- `ZAC_IMMEDIATE_CALLBACK_FNC` hook: a shell function called directly inside the
  signal handler in every shell, before the next prompt. Intended for
  lightweight, instant in-shell updates (environment assignments only).
- `editors/emacs/zac-theme-autodetection.el`: a generic Emacs module that watches
  the appearance file and calls a user-supplied callback on every change.
  Released as a separate artifact. No external packages required; works with
  built-in themes such as `modus-operandi` and `modus-vivendi-tinted` (Emacs 28
  or newer).

### Changed

- `ZAC_CALLBACK_FNC` is renamed to `ZAC_DEFERRED_CALLBACK_FNC`, to reflect its
  semantics. The old name is still accepted as a legacy alias.
- Unified dispatch pipeline: `bin/appearance-dispatch dispatch <0|1>` runs
  `ZAC_IO_CMD` once, under a lock and idempotently, writes both ground truths
  (tmux `@dark_appearance` and the cache file), and signals all registered shells
  in a single call.
- Rewrote the README sections for callbacks, WezTerm watcher configuration, and
  zinit installation.
- Replaced the Catppuccin-based Emacs example with a self-contained example that
  uses the built-in modus themes, and documented the `enable-theme-functions`
  hook pattern (Emacs 29 or newer) for harmonizing package faces.

### Fixed

- `zac status` stores the cached appearance value in `$REPLY`, consistent with
  the other plugin conventions.
- Implicit global `REPLY` inside functions: it is now declared with `typeset -g`.

## [1.0.2] - 2026-02-25

### Fixed

- Debug mode (`zac debug 1`) did not display the correct state of the internal
  variables.

### Changed

- Improved the WezTerm configuration example, so that paths resolve correctly and
  `zac` is triggered as intended.

## [1.0.1] - 2026-02-08

No release notes were provided for this version.

## [1.0.0] - 2026-02-07

First release.

[Unreleased]: https://github.com/alberti42/zsh-appearance-control/compare/v2.2.0...HEAD
[2.2.0]: https://github.com/alberti42/zsh-appearance-control/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/alberti42/zsh-appearance-control/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/alberti42/zsh-appearance-control/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/alberti42/zsh-appearance-control/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/alberti42/zsh-appearance-control/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/alberti42/zsh-appearance-control/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/alberti42/zsh-appearance-control/releases/tag/v1.0.0
