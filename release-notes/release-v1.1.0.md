# Change log

## New features

- New `ZAC_IO_CMD` hook: a single executable path run once per appearance change by the dispatcher, before any shell is notified. Intended for heavy I/O such as writing tool config files to disk.
- New `ZAC_IMMEDIATE_CALLBACK_FNC` hook: a shell function called directly inside the signal handler in every shell, before the next prompt. Intended for lightweight, instant in-shell updates (env var assignments only).
- `ZAC_CALLBACK_FNC` has been renamed to `ZAC_DEFERRED_CALLBACK_FNC` to better reflect its semantics. The old name is still accepted as a legacy alias and will continue to work for the foreseeable future.
- Unified dispatch pipeline: `bin/appearance-dispatch dispatch <0|1>` now runs `ZAC_IO_CMD` (once, under a lock, idempotent), writes both ground truths (tmux `@dark_appearance` and cache file), and signals all registered shells in a single call.

## Bug fixes

- `zac status` now correctly stores the cached appearance value in `$REPLY`, consistent with other plugin conventions.
- Fixed implicit global `REPLY` variable inside functions — now correctly declared with `typeset -g`.

## Emacs integration

- Added `editors/emacs/zac-theme-autodetection.el`, a generic Emacs module that watches the zsh-appearance-control appearance file and calls a user-supplied callback on every appearance change. Released as a separate artifact (`zac-emacs-v1.1.0.zip`). No external packages required — works with built-in themes such as `modus-operandi` / `modus-vivendi-tinted` (Emacs 28+).

## Docs

- Rewrote the README sections for callbacks, WezTerm watcher configuration, and zinit installation.
- Replaced the Catppuccin-based Emacs example with a self-contained example using built-in modus themes. Documents the `enable-theme-functions` hook pattern (Emacs 29+) for harmonizing package faces after theme switches.
