#!/usr/bin/env zsh

###################################################
#  zsh-appearance-control (c) 2026 Andrea Alberti
###################################################

# This plugin keeps a small zsh-side cache of whether "dark mode" is enabled
# and uses that value to (optionally) update prompt-related variables.
#
# Design goals:
# - Do nothing in non-interactive shells.
# - Keep signal handlers cheap: TRAPUSR1 only marks the state as needing sync.
# - Avoid zsh autoload/fpath pollution.
# - Eager-load the core runtime needed for hooks/signal handling.
# - Optional zcompile for faster subsequent loads (ZAC_COMPILE=1 by default).
# - Lazy-load user utilities (e.g. `zac`) and OS setters.
#
# Glossary:
# - "is_dark": boolean 0/1 representing dark mode enabled.
# - "ground truth": the authoritative source of is_dark.
#   For now: in tmux it is tmux option @dark_appearance; non-tmux is TODO.
#
# Entry points:
# - Hook-driven refresh: precmd/preexec call _zac.sync when needs_sync=1.
# - Signal-driven refresh: external tools (e.g. WezTerm) send USR1 -> needs_sync=1.
# - User-driven change: `zac dark|light|toggle` sets OS dark mode (macOS).

# Prompt/plugin behavior only: do nothing in non-interactive shells.
[[ -o interactive ]] || return 0

typeset -gA _zac

_zac[meta.plugin_dir]=${${(%):-%x}:a:h}

####################################################################
# Bootstrap
#
# This file is the only file sourced by the plugin manager.
# It must:
# - ensure we are interactive
# - establish the global state map
# - find the plugin directory
# - source the core module (which compiles/sources its deps and self-inits)
####################################################################

# Bootstrap-time no-op logger.
# Ensure we always have a safe logger (bootstrap normally defines this).
# The debug module overwrites _zac.debug.log when ZAC_DEBUG=1.
function _zac.debug.log() { return 0 }

# Load core.
# - Core defines module compilation/sourcing helpers.
# - Core sources its hard dependencies.
# - Core self-initializes by calling _zac.init once at EOF.
builtin source "${_zac[meta.plugin_dir]}/src/core.zsh"

# Optional extras (lazy-loaded).

if (( _zac[cfg.enable_ssh_tmux] )) && (( ${+functions[ssh-tmux]} == 0 )); then
  function ssh-tmux() {
    # Lazy stub: source module and tail-call the real ssh-tmux().
    builtin emulate -LR zsh -o warn_create_global -o no_short_loops

    _zac.module.compile_and_source src/ssh-tmux.zsh || return $?
    ssh-tmux "$@"
  }

  # Enforce the same autocompletion for ssh-tmux as for ssh (when available).
  (( ${+functions[compdef]} )) && compdef ssh-tmux=ssh
fi

function zac() {
  # Lazy stub: source CLI (+ platform) and tail-call the real zac().
  #
  # Note: we intentionally do NOT guard this with a "loaded" flag.
  # The intended pattern is: sourcing src/cli.zsh overwrites this stub.

  case $OSTYPE in
    (darwin*) _zac.module.compile_and_source src/platform/darwin.zsh || return $? ;;
    (*)       _zac.module.compile_and_source src/platform/unsupported.zsh || return $? ;;
  esac

  _zac.module.compile_and_source src/cli.zsh || return $?

  zac "$@"
}
