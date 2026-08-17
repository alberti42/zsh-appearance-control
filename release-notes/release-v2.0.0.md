# Change log

## Breaking changes

- **The cache file is the only ground truth.** The plugin no longer reads the
  tmux option `@dark_appearance`, and `src/platform/tmux.zsh` is removed. Shells
  read `$ZAC_CACHE_DIR/appearance` in tmux and outside it.

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
  yet was killed. If your plugin manager loads the plugin lazily, a very young
  shell may miss one change; it reads the file at load instead.

- **`ssh-tmux` hands the appearance to the remote host through the file**, by
  running `appearance-dispatch` there, or by writing the default remote cache
  file. It no longer sets a tmux option on the remote server.

## New features

- Documented tmux hooks as a watcher: `client-dark-theme` and
  `client-light-theme` (tmux 3.6 or newer). tmux detects the theme of the
  attached terminal, which also works for a session attached over ssh.

## Bug fixes

- The dispatch lock is now stale-proof. A killed dispatch used to leave
  `io.lock` behind, and every later dispatch failed with
  `failed to acquire lock`. The lock records its owner PID, a lock whose owner
  is dead is stolen, and `INT`/`HUP`/`TERM`/`EXIT` release it.

- `src/ssh-tmux.zsh` ended on a failing `compdef` test, so the module loader
  reported a bogus load failure in shells without `compdef`.

## Performance

- Shell startup is about 22 ms faster. `_zac.cache.pid.register` no longer forks
  `mkdir`, `chmod`, `ps` and `date`; it uses `$EPOCHSECONDS` and the `zf_*`
  builtins from `zsh/files`. The pid file now stores the registration time, and
  the dispatcher accepts a shell whose start time is not later than that value.

- `sync` no longer forks. Reading the ground truth is a builtin read, where the
  old tmux query cost about 6 ms.
