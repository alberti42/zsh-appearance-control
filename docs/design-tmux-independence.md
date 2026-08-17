# Design note: less tmux, and remote sessions by connection ID

Status: agreed direction, not implemented. Written 2026-08-17.

## Principle

tmux is a **consumer** of the appearance, not its source.

Neither the plugin nor `bin/appearance-dispatch` touches a tmux option any
more. A user who themes tmux (`examples/tmux/catppuccin.conf`) sets
`@dark_appearance` from their `ZAC_IO_CMD` script, exactly like any other
consumer. Status: done, see the commits of 2026-08-17.

## New ground truth

A file, chosen by scope:

| Scope | File | Read by |
|---|---|---|
| per user on a host | `$ZAC_CACHE_DIR/appearance` | shells with no connection ID |
| one ssh connection | `$ZAC_CACHE_DIR/appearance.<ID>` | shells carrying that ID |

Benefits: no fork in `sync` (a builtin read replaces `tmux show-options`, which
costs about 6 ms), no tmux-versus-file precedence rule, and remote sessions work
without tmux.

## The connection ID

Two identifiers, do not confuse them:

| Name | Scope | Purpose |
|---|---|---|
| connection ID | one per ssh connection | says which local terminal the session belongs to; names the value file |
| `pids/<PID>` entry | one per zsh process | says which process to signal; records the connection ID it belongs to |

Flow:

1. `ssh-tmux` mints an ID locally and passes it in the remote command line, so
   the ID is visible in the argv of the local `ssh` process.
2. Remote shells read the ID from their environment and write it into their
   `pids/<PID>` entry.
3. On a local appearance change, the local side lists running `ssh` processes,
   parses the IDs and the target hosts from argv, and runs the remote dispatcher
   once per session: `appearance-dispatch dispatch <0|1> --id <ID>`.
4. The remote dispatcher writes `appearance.<ID>` and signals only the pid
   entries that carry that ID.

Why the value file is still needed: `USR1` carries no payload, so the shell must
read the new value somewhere.

## tmux panes and the ID

A new pane inherits the tmux session environment, not the environment of your
current client. tmux refreshes that environment on attach for the variables in
`update-environment`, so the remote tmux config needs:

```
set-option -ga update-environment " ZAC_CONN_ID"
```

Existing panes keep the old ID; panes created after the attach get the current
one. A wrong theme in an old pane is acceptable.

## Open points

- Where the local list of open sessions lives: parsed from `ps` on demand, or a
  registry written by `ssh-tmux`.
- Whether the remote call reuses the open connection (ssh `ControlMaster`,
  roughly 10 to 30 ms) or opens a new one (hundreds of milliseconds). The call
  must run in the background and must never delay the local prompt.
- Cleanup of stale `appearance.<ID>` files when a connection ends.
- Whether per-connection scoping is worth it at all: one person uses one theme
  at a time, so the per-user file is usually the right scope.
- Migration: keep reading the tmux option while old remote hosts still run the
  previous version.
