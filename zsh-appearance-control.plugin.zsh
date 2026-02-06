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

typeset -gA _zsh_appearance_control

_zsh_appearance_control[plugin.dir]=${${(%):-%x}:a:h}

#+#+#+#+############################################################
# Bootstrap
#
# This file is the only file sourced by the plugin manager.
# It must:
# - ensure we are interactive
# - establish the global state map
# - find the plugin directory
# - compile/source core modules
# - call the single core entrypoint: _zac.init
#+#+#+#+############################################################

# Bootstrap-time no-op logger.
# The debug module overwrites _zac.debug.log when ZAC_DEBUG=1.
function _zac.debug.log() { return 0 }

function _zac.module.source() {
  # Source a module from src/ with optional compilation.
  local module=$1
  local dir=${_zsh_appearance_control[plugin.dir]}
  local compile=${ZAC_COMPILE:-1}

  local script="$dir/$module"
  local compiled_script="${script}.zwc"

  if (( compile )); then
    if [[ ! -f $compiled_script || $script -nt $compiled_script ]]; then
      zcompile -Uz -- "$script" "$compiled_script" 2>/dev/null
    fi
  fi

  builtin source "$script"
}

# Eager-load core runtime needed for hooks and USR1-driven sync.
_zac.module.source src/platform/tmux.zsh
_zac.module.source src/platform/ground_truth.zsh
_zac.module.source src/core.zsh

(( $+functions[_zac.init] )) && _zac.init

function zac() {
  # Lazy stub: source CLI (+ platform) on first use.
  (( ${+_zsh_appearance_control[_cli_loaded]} )) || _zsh_appearance_control[_cli_loaded]=0
  if (( ! _zsh_appearance_control[_cli_loaded] )); then
    _zsh_appearance_control[_cli_loaded]=1

    case $OSTYPE in
      (darwin*) _zac.module.source src/platform/darwin.zsh ;;
      (*)       _zac.module.source src/platform/unsupported.zsh ;;
    esac

    _zac.module.source src/cli.zsh
  fi

  zac "$@"
}
