# Real-world example: one author's complete zac setup

The main README documents each extension point in isolation. These three files
are the same points as they are actually used, taken from a private dotfiles
repository — a working configuration that themes a dozen tools, warts included.

They are **snapshots, not drop-ins**: the paths, the tool list and the colour
schemes are someone else's. Read them for the shape.

| File | Role | Extension point |
|---|---|---|
| `zac.zsh` | plugin wiring + inline callback | `ZAC_IMMEDIATE_CALLBACK_FNC`, zinit load |
| `zac-io-cmd.zsh` | rewrite config files on a transition | `ZAC_IO_CMD` (read by `bin/appearance-dispatch`) |
| `zac-tmux-cmd.zsh` | tmux options that live in the server | plain consumer, shared by the io script and `tmux.conf` |

Their original location is `zinit/src/zac/` in that repository, and the watcher
that drives them is `watchers/macos` on the Mac and `watchers/linux` on the
Ubuntu box, both calling `bin/appearance-dispatch`.

## How the three fit together

```
OS toggles appearance
   │
   ├─ watcher  ──►  appearance-dispatch dispatch <0|1>
   │                   ├─ runs ZAC_IO_CMD           →  zac-io-cmd.zsh
   │                   │     └─ runs, at its end    →  zac-tmux-cmd.zsh
   │                   ├─ writes the cache file (ground truth)
   │                   └─ signals the registered shells with USR1
   │
   └─ in each shell: TRAPUSR1
         ├─ ZAC_IMMEDIATE_CALLBACK_FNC  →  __my_appearance_immediate  (zac.zsh)
         └─ at the next prompt: sync + the deferred callback
```

`zac-tmux-cmd.zsh` is also run by `tmux.conf` at server start, which is the point
of splitting it out: a tmux server that starts later has lost the in-memory
options, and re-running the whole io script would be wasteful.

## What is worth copying

**From `zac.zsh`** — the inline callback obeys the hard rule for
`ZAC_IMMEDIATE_CALLBACK_FNC`: assignments and `zstyle` only, no subshells, no
external commands, no output. It runs inside `TRAPUSR1`, so anything heavier can
wedge the shell. Note also the load line: `atload'zac sync && __my_appearance_immediate "$REPLY"'`
primes the state at load time, so the first prompt is already themed rather than
waiting for the first change.

**From `zac-io-cmd.zsh`** — the three-way status per step: `0` applied, `2`
skipped because the tool is not installed on this host, `1` real failure, and
only `1` aborts. This matters more than it looks: a non-zero `ZAC_IO_CMD` aborts
the whole dispatch, so no ground truth is written and no shell is signalled. A
single missing `~/.claude.json` once left an entire machine with no appearance at
all. Also worth stealing: the values are chosen once into variables instead of
duplicating every command in a dark/light `if`-`else` (the duplicated version had
already drifted), and the file mode is preserved across the temp-file rewrite.

**From `zac-tmux-cmd.zsh`** — tmux is a consumer like any other tool. Since 2.0.0
neither the plugin nor the dispatcher touches a tmux option, so `@dark_appearance`
is yours to set; keeping the server-resident subset in one small script lets the
transition path and the server-start path share a single source of truth.

## What you must replace

These are the external things the files assume; none of them come from this
plugin:

| Referenced | What it is |
|---|---|
| `$DOTFILES_DIR`, `$XDG_*` | set in that repo's `.zshenv` |
| `$LS_COLORS_FILES`, `$FZF_DEFAULT_OPTS_CATPPUCCIN`, `$FSH_CACHE_FILES` | associative arrays built by sibling snippets (vivid, fzf, fast-syntax-highlighting) |
| `__zcompile_if_needed_and_source` | that repo's compile-and-source helper |
| `patina`, `vivid`, `yazi`, `btop`, `opencode`, `gemini`, `claude` | the tools being themed |
| `_zsh_opencode_tab`, `+zi-log` | other plugins |

## Caveats

- Not refreshed automatically. `make bump-version` does not touch these files,
  and they will drift from their originals; the date in each header says when the
  snapshot was taken.
- Not part of the release artifacts. `examples/` is excluded from the plugin zip
  on purpose — these are reading material, not something to install.
- The `sed` rewrites assume the exact shape of each config file. They are the
  fragile kind of automation that works well for one person and needs adjusting
  for the next.
