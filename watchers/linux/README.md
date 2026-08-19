# zac-watch-linux

A systemd **user** service that watches the desktop's light/dark preference and
calls `appearance-dispatch` when it changes. The Linux counterpart of
`watchers/macos/zac-watch-macos`, and the same shape: it answers one question —
*did the appearance change?* — and hands the answer to the dispatcher.

```
appearance-dispatch dispatch <0|1>
```

Everything else (`ZAC_IO_CMD`, the ground truth file, the `USR1` signals) is the
dispatcher's job.

Unlike the macOS watcher this is a zsh script, not a compiled binary: there is
nothing to build, nothing to sign, and no per-architecture artifact.

## Requirements

- A desktop that reports a colour-scheme preference:
  - **GNOME 42 or newer** — Ubuntu 22.04 and later, Fedora 36 and later; or
  - any desktop whose **`xdg-desktop-portal`** implements
    `org.freedesktop.appearance` (KDE Plasma 5.24+, and others).
- A **session D-Bus** — that is, a graphical session. The watcher refuses to
  start without one instead of running blind.
- `systemd --user`, and `zsh` (which you have, this being a zsh plugin).
- `gdbus` (package `libglib2.0-bin` on Debian/Ubuntu) for the portal backend, or
  `gsettings` (same package) for the GNOME backend.

Older desktops with no dark-mode preference are **not supported**: there is no
signal to watch.

## Backends

Auto-detected, in this order. Force one with `ZAC_WATCH_BACKEND`.

| Backend | Trigger | Value read from |
|---|---|---|
| `portal` (preferred) | `gdbus monitor` on `org.freedesktop.portal.Settings.SettingChanged` | `Settings.ReadOne('org.freedesktop.appearance', 'color-scheme')`, falling back to `Read` |
| `gsettings` | `gsettings monitor org.gnome.desktop.interface color-scheme` | `gsettings get …` |
| `custom` | `$ZAC_WATCH_MONITOR_CMD` | `$ZAC_WATCH_READ_CMD` |

The portal comes first because it is the cross-desktop interface — the same one
browsers use for `prefers-color-scheme` — and it answers on GNOME too.

Values follow the plugin's existing GNOME mapping exactly
(`src/platform/linux-gnome.zsh`): dark is `prefer-dark` (portal `1`), and
everything else — `default`, `prefer-light`, portal `0` (no preference) and `2` —
is light. Two different answers to "is it dark" would be a second ground truth.

**The signal is only a trigger.** The value is always re-read afterwards, exactly
as on macOS: a desktop may emit several signals per change, and Ubuntu's accent
colour changes touch neighbouring keys. Triggers are coalesced
(`ZAC_WATCH_DEBOUNCE_MS`, default 200 ms), so a burst yields one dispatch.

## Which launcher: systemd or XDG autostart?

Ask your session:

```zsh
systemctl --user is-active graphical-session.target
```

| Answer | Use | Why |
|---|---|---|
| `active` | the **systemd** unit (`make watcher-linux-install`) | the session is integrated with `systemd --user`: one bus, supervision, journal, restart-on-failure |
| `inactive` | the **autostart** entry (`make watcher-linux-autostart-install`) | nothing would ever start the unit, and the session has its own D-Bus |

A plain local GNOME or KDE login gives `active`. An **NX/NoMachine, xrdp or VNC**
session usually gives `inactive`, and there it also runs its **own D-Bus daemon**
(socket in `/tmp`, not `/run/user/$UID/bus`). Two consequences, both of which look
like "the watcher is broken":

- `WantedBy=graphical-session.target` never fires, so the unit does not start at
  login even though `systemctl --user enable` succeeded;
- a unit that *is* started talks to the systemd bus, not the session bus, so it
  reads the right value at startup and is never told about a change.

The autostart entry avoids both: the session launches it, so it inherits that
session's bus and `DISPLAY` by construction, and it is re-launched per session —
which matters because the `/tmp` socket path changes with every login.

Verified on Ubuntu GNOME reached over NoMachine: after a reboot and a fresh
login, the watcher runs and follows the theme with no manual step.

If you would rather keep systemd on such a session, you must hand it the address
after every login:

```zsh
systemctl --user import-environment DBUS_SESSION_BUS_ADDRESS DISPLAY XAUTHORITY
systemctl --user restart zac-watch-linux.service
```

(`dbus-update-activation-environment --systemd` does *not* work there: it reaches
systemd through the session bus, where systemd is not listening — the error is
`Method "SetEnvironment" … doesn't exist`.)

The watcher checks this at startup and warns when the desktop's bus differs from
its own, so the failure announces itself in the log rather than being silent.

## Install

From the repository root:

```zsh
make watcher-linux-install \
  IO_CMD=$HOME/path/to/your/io-script          # optional
```

That copies the script to `~/.local/bin/zac-watch-linux`, writes
`~/.config/systemd/user/zac-watch-linux.service`, reloads the user daemon and
enables the service now.

```zsh
make watcher-linux-status        # systemctl --user status
make watcher-linux-uninstall     # disable and remove
journalctl --user -u zac-watch-linux -f
```

Or, for a session that is not systemd-integrated (see above):

```zsh
make watcher-linux-autostart-install \
  IO_CMD=$HOME/path/to/your/io-script
make watcher-linux-autostart-uninstall
```

The autostart entry writes `~/.config/autostart/zac-watch-linux.desktop` and
takes effect at the next login; its output goes to the session error log
(`~/.xsession-errors` on X11), so debug by running the watcher in the foreground.
Do not install both launchers at once.

Overrides, same names as the macOS target:

| Variable | Default | Meaning |
|---|---|---|
| `PREFIX` | `~/.local` | script goes to `$PREFIX/bin/zac-watch-linux` |
| `DISPATCH_BIN` | `$(CURDIR)/bin/appearance-dispatch` | dispatcher path baked into the unit |
| `IO_CMD` | empty | your `ZAC_IO_CMD` script |
| `AGENT_PATH` | `~/.local/bin` + system dirs | `PATH` for the service |

### By hand

```zsh
install -m 755 zac-watch-linux ~/.local/bin/
sed -e 's|@WATCHER_BIN@|'"$HOME"'/.local/bin/zac-watch-linux|' \
    -e 's|@DISPATCH_BIN@|/path/to/bin/appearance-dispatch|' \
    -e 's|@IO_CMD@||' -e 's|@PATH@|'"$PATH"'|' \
    systemd/zac-watch-linux.service.in \
  > ~/.config/systemd/user/zac-watch-linux.service
systemctl --user daemon-reload
systemctl --user enable --now zac-watch-linux.service
```

## Environment

The watcher reads only these:

| Variable | Default | Meaning |
|---|---|---|
| `ZAC_DISPATCH` | looked up in `PATH` | absolute path to `bin/appearance-dispatch`. **Required** in the unit. |
| `ZAC_WATCH_BACKEND` | `auto` | `portal`, `gsettings`, `custom` |
| `ZAC_WATCH_DEBOUNCE_MS` | `200` | coalescing window |
| `ZAC_WATCH_RETRY_MS` | `3000` | delay before the single retry of a failed dispatch; `0` disables it |
| `ZAC_WATCH_MONITOR_CMD` | — | custom backend: prints one line per change, never exits |
| `ZAC_WATCH_READ_CMD` | — | custom backend: prints `1` or `0` |
| `ZAC_WATCH_PORTAL_TIMEOUT_MS` | `3000` | timeout of a portal call. `gdbus` waits 25 s by default, which makes the fallback to `gsettings` look like a hang at login |
| `ZAC_WATCH_DETECT_TRIES` | `5` | detection passes before giving up |
| `ZAC_WATCH_DETECT_WAIT_S` | `3` | wait between detection passes |

Everything else is inherited by the dispatcher unchanged. Set `ZAC_IO_CMD`,
`ZAC_CACHE_DIR` and `PATH` in the unit, not on the watcher's command line.

## Restart semantics

`gdbus monitor` and `gsettings monitor` die when the session bus or the portal
restarts. The watcher does not try to be clever about that: it logs, exits
non-zero, and lets systemd restart it (`Restart=always`, `RestartSec=5`). The
unit also carries `StartLimitBurst=5` per minute so a broken setup stops rather
than spins.

A failed dispatch (non-zero `ZAC_IO_CMD`) is retried **once** after
`ZAC_WATCH_RETRY_MS`. Retrying is safe because a failed dispatch writes no
ground truth and signals no shell; a loop would hammer a broken script.

## Debugging

```zsh
./zac-watch-linux --print     # 1 = dark, 0 = light, exits
./zac-watch-linux --once      # dispatch the current appearance once
ZAC_WATCH_BACKEND=gsettings ZAC_DISPATCH=/path/to/appearance-dispatch \
  ./zac-watch-linux           # run in the foreground

journalctl --user -u zac-watch-linux -n 50 --no-pager
```

Common outcomes:

- *no session D-Bus* — the service was started outside the graphical session.
  Check `systemctl --user show-environment | grep DBUS`, and that the unit is
  wanted by `graphical-session.target`.
- *no usable backend* — neither the portal setting nor the GNOME key answered.
  Try `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadOne org.freedesktop.appearance color-scheme`
  and `gsettings get org.gnome.desktop.interface color-scheme` by hand.
- the log says `already dark, skipped` — a trigger arrived but the value did not
  change. Normal: accent-colour and theme changes also touch these settings.
- *the appearance portal did not answer; trying gsettings* — the portal is D-Bus
  activated and is often not up yet a second after login, which is exactly when
  this service starts. On GNOME the `gsettings` backend is equivalent, so this is
  harmless; force `ZAC_WATCH_BACKEND=portal` if you want the service to wait for
  the portal instead (it will retry `ZAC_WATCH_DETECT_TRIES` times).
- *no backend yet (attempt n/5)* — the session is still coming up. The watcher
  retries rather than dying, so it does not burn the unit's start limit during a
  slow login.
- `ZAC_IO_CMD failed; aborting` in the journal is **your** io script failing, not
  the watcher: the dispatcher then writes no ground truth and signals no shell,
  by design. A script shared with macOS often needs guards on Linux — check that
  every file it rewrites exists on this host.

The `custom` backend is also the test harness: point it at a script that prints
a line per change and another that prints the state, and the whole loop can be
exercised without a desktop.

## When a change is not noticed

The startup dispatch works but toggling the theme does nothing? Those are two
different code paths: reading the value goes through dconf, which reads its
database file directly and needs no bus, while *notifications* only arrive over
the session D-Bus. A watcher can therefore read correctly and still never be
told about a change.

Run it in the foreground with the same backend the service chose, and with the
raw monitor stream shown:

```zsh
ZAC_WATCH_BACKEND=gsettings ZAC_WATCH_VERBOSE=1 \
ZAC_DISPATCH=/path/to/bin/appearance-dispatch ZAC_CACHE_DIR=/tmp/zac-t \
  ./zac-watch-linux
```

| What you see when toggling | Meaning |
|---|---|
| no `monitor:` line at all | the monitor is not delivering; try `ZAC_WATCH_BACKEND=portal` |
| `monitor:` lines but no `change:` | the line was not recognised as a trigger (report it) |
| works here, not as a service | the service inherited a different session bus |

For the last case, compare the two:

```zsh
tr '\0' '\n' < /proc/$(systemctl --user show -p MainPID --value zac-watch-linux)/environ \
  | grep -E 'DBUS|XDG_RUNTIME'
echo "$DBUS_SESSION_BUS_ADDRESS"
systemctl --user is-active graphical-session.target
```

Forcing the portal backend in the unit is the usual answer, because the portal is
D-Bus activated and reachable as soon as the session is up:

```ini
Environment=ZAC_WATCH_BACKEND=portal
```
