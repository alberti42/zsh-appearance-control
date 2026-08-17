# zac-watch-macos

A tiny launchd agent that watches the macOS dark/light setting and calls
`appearance-dispatch` when it changes. It closes the "you need an external
watcher" gap for people who do not use WezTerm or tmux 3.6 hooks: it works with
any terminal, including Terminal.app, and it also fires when macOS switches
appearance automatically at sunset.

It is deliberately dumb. It answers one question — *did the appearance change?* —
and hands the answer to `bin/appearance-dispatch`:

```
appearance-dispatch dispatch <0|1>
```

Everything else (`ZAC_IO_CMD`, the ground truth file, the `USR1` signals) is the
dispatcher's job.

## How it detects the change

- It observes the distributed notification `AppleInterfaceThemeChangedNotification`.
- The notification is only a **trigger**. The value is always re-read from the
  user defaults (`AppleInterfaceStyle`), because the notification can arrive a
  moment before the defaults are updated, and it usually arrives more than once
  per change.
- Triggers are coalesced (150 ms by default) and dispatches are serialized, so a
  burst produces exactly one dispatch.
- Foundation only: no AppKit, no `NSApplication`, no app bundle, no Dock icon.
  Idle cost is a sleeping run loop.

## Build

Requires the Swift toolchain (Xcode command line tools).

```zsh
cd watchers/macos
swift build -c release
.build/release/zac-watch-macos --print     # 1 = dark, 0 = light
```

From the repository root you can also use the Makefile:

```zsh
make watcher                # build
make watcher-install        # build, install binary + agent, load it
make watcher-status         # launchctl print
make watcher-uninstall      # unload and remove
```

`watcher-install` accepts overrides:

| Variable | Default | Meaning |
|---|---|---|
| `PREFIX` | `~/.local` | binary goes to `$PREFIX/bin/zac-watch-macos` |
| `DISPATCH_BIN` | `$(CURDIR)/bin/appearance-dispatch` | dispatcher path baked into the agent |
| `IO_CMD` | empty | your `ZAC_IO_CMD` script |
| `AGENT_PATH` | homebrew + `~/.local/bin` + system dirs | `PATH` for the agent |
| `LOG_DIR` | `~/Library/Logs` | agent log directory |

Example:

```zsh
make watcher-install \
  IO_CMD=$HOME/.config/dotfiles/zinit/src/zac/zac-io-cmd.zsh \
  DISPATCH_BIN=$HOME/.config/dotfiles/oh-my-zsh/custom/plugins/zsh-appearance-control/bin/appearance-dispatch
```

## Install by hand

1. Copy the binary somewhere on your `PATH`, e.g. `~/.local/bin/zac-watch-macos`.
2. Substitute the `@…@` placeholders in
   `launchd/com.github.alberti42.zac-watch-macos.plist.in` and write the result to
   `~/Library/LaunchAgents/com.github.alberti42.zac-watch-macos.plist`.
3. Load it:

```zsh
launchctl bootstrap gui/$(id -u) \
  ~/Library/LaunchAgents/com.github.alberti42.zac-watch-macos.plist
```

Unload with `launchctl bootout gui/$(id -u)/com.github.alberti42.zac-watch-macos`.

The agent sets `LimitLoadToSessionType = Aqua` and must be loaded in the `gui/`
domain: a background-session job never receives the appearance notification.

## Environment

The watcher itself reads only these:

| Variable | Default | Meaning |
|---|---|---|
| `ZAC_DISPATCH` | looked up in `PATH` | absolute path to `bin/appearance-dispatch`. **Required** in the agent. |
| `ZAC_WATCH_DEBOUNCE_MS` | `150` | coalescing window |
| `ZAC_WATCH_RETRY_MS` | `3000` | delay before the single retry of a failed dispatch; `0` disables it |

Everything else in the environment is inherited by the dispatcher unchanged.
That is how `ZAC_IO_CMD` and `ZAC_CACHE_DIR` are passed: set them in the plist,
not on the command line of the watcher.

### About `PATH`

launchd gives a job a bare `PATH=/usr/bin:/bin:/usr/sbin:/sbin` when the plist
does not set one. `appearance-dispatch` runs `/bin/zsh -f` and only needs
`/bin` and `/usr/bin`, so it works either way — but your `ZAC_IO_CMD` script
usually calls tools from Homebrew or `~/.local/bin`. Two ways to cover that:

- set `PATH` in the plist (what `make watcher-install` does), or
- give your io script a `#!/bin/zsh` shebang **without** `-f`, so it sources
  `~/.zshenv` and rebuilds `PATH` itself.

Setting it in the plist is worth doing regardless: it makes the agent
deterministic.

## Signing and Gatekeeper

The binary attached to a GitHub release is signed with a Developer ID
certificate, built with the hardened runtime and a secure timestamp, and
notarized by Apple. It therefore runs from a browser download without any
Gatekeeper dance.

The notarization ticket is **not stapled**, and cannot be: `stapler` handles
disk images, code-signed bundles and installer packages, and a bare Mach-O
executable is none of them. The ticket is registered against the binary's
cdhash instead, so a quarantined copy is checked online the first time it runs.

A binary you build yourself (`make watcher`) carries only the ad-hoc signature
the linker gives it. That is fine: a locally built file is never quarantined.
If you ever end up with a quarantined unsigned copy — for example one built on
another machine and moved over — clear the flag:

```zsh
xattr -dr com.apple.quarantine /path/to/zac-watch-macos
```

To sign your own build, pass an identity to the packaging script:

```zsh
ZAC_CODESIGN_ID="Developer ID Application: Your Name (TEAMID)" \
  zsh -f bin/make-watcher v9.9.9
```

## Retry semantics

A failed dispatch (non-zero `ZAC_IO_CMD`) writes no ground truth and signals no
shell, so retrying it is safe. The watcher retries **once** after
`ZAC_WATCH_RETRY_MS`; a script that is genuinely broken must not turn into a
loop. Failures are logged with the dispatcher's exit status.

## Debugging

```zsh
# Run in the foreground with the same environment the agent would have:
ZAC_DISPATCH=/path/to/bin/appearance-dispatch \
ZAC_IO_CMD=/path/to/io-script \
  .build/release/zac-watch-macos

# One-shot dispatch of the current appearance (exits with the dispatcher status):
ZAC_DISPATCH=/path/to/bin/appearance-dispatch .build/release/zac-watch-macos --once

# Agent log
tail -f ~/Library/Logs/zac-watch-macos.log
```

If the log shows `watching (...)` but nothing happens when you toggle
appearance in System Settings, check that the job is in the `gui/` domain
(`make watcher-status`) and not `system/`.
