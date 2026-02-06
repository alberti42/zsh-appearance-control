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
# - Avoid zsh autoload/fpath pollution: use an explicit lazy loader.
# - Optional zcompile for faster subsequent loads (ZAC_COMPILE=1 by default).
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

# User-Configurable Options
#
# - callback.fnc: optional function name, called as: $callback <is_dark>
#   Set via env ZAC_CALLBACK_FNC or runtime via: `zac callback <fn>`.
: ${_zsh_appearance_control[callback.fnc]:=''}
: ${_zsh_appearance_control[callback.fnc]:=${ZAC_CALLBACK_FNC:-''}}
# - on_source.redraw_prompt: if sourced while already in ZLE, redraw prompt
: ${_zsh_appearance_control[on_source.redraw_prompt]:=${ZAC_ON_SOURCE_REDRAW_PROMPT:-0}}
# - on_change.redraw_prompt: if a sync runs in ZLE and is_dark changes, redraw
: ${_zsh_appearance_control[on_change.redraw_prompt]:=${ZAC_ON_CHANGE_REDRAW_PROMPT:-0}}

# Internal State Variables
#
# - is_dark: cached boolean 0/1 (may be empty until first sync or user command)
: ${_zsh_appearance_control[is_dark]:=''}
# - needs_sync: boolean 0/1; when 1, hooks call _zac.sync
: ${_zsh_appearance_control[needs_sync]:=1}
# - needs_init_propagate: boolean 0/1; used to propagate once after logon
: ${_zsh_appearance_control[needs_init_propagate]:=0}
# - last_sync_changed: boolean 0/1; whether last sync changed cached is_dark
: ${_zsh_appearance_control[last_sync_changed]:=0}
# - logon: boolean 0/1; while 1, _zac.propagate avoids touching other plugins
: ${_zsh_appearance_control[logon]:=0}

function _zac._load() {
  # Lazy loader: sources the real implementation modules the first time any
  # entry point runs. Sourcing overwrites the stub functions below.
  (( ${+_zsh_appearance_control[_loaded]} )) && return 0
  _zsh_appearance_control[_loaded]=1

  local dir=${_zsh_appearance_control[plugin.dir]}
  local compile=${ZAC_COMPILE:-1}

  local -a modules
  # Base modules always loaded.
  modules=(
    src/core.zsh
    src/platform/tmux.zsh
  )

  case $OSTYPE in
    # OS-specific implementations are loaded by platform.
    (darwin*) modules+=(src/platform/darwin.zsh) ;;
    (*)       modules+=(src/platform/unsupported.zsh) ;;
  esac

  modules+=(
    src/platform/ground_truth.zsh
    src/cli.zsh
  )

  local module script compiled_script
  for module in $modules; do
    script="$dir/$module"

    if (( compile )); then
      # Compile only when the .zwc is missing or older than the source.
      compiled_script="${script}.zwc"
      if [[ ! -f $compiled_script || $script -nt $compiled_script ]]; then
        zcompile -Uz -- "$script" "$compiled_script" 2>/dev/null
      fi
    fi

    builtin source "$script"
  done

  (( $+functions[_zac.init] )) && _zac.init
}

function zac() {
  # Stub: load the implementation and tail-call the real zac().
  _zac._load || return $?
  zac "$@"
}

function _zac.precmd() {
  # Stub hook: load, then tail-call the real _zac.precmd().
  _zac._load || return $?
  _zac.precmd "$@"
}

function _zac.preexec() {
  # Stub hook: load, then tail-call the real _zac.preexec().
  _zac._load || return $?
  _zac.preexec "$@"
}

if (( ${precmd_functions[(I)_zac.precmd]} == 0 )); then
  # Register the hook stubs (real functions overwrite these after load).
  #
  # Why precmd:
  # - Runs right before a prompt is drawn.
  # - If USR1 arrives while a command is running, precmd is the first chance to
  #   apply the change as soon as that command finishes (no extra Enter needed).
  # - Also a natural place for one-time "first prompt" initialization.
  precmd_functions+=(_zac.precmd)
fi

if (( ${preexec_functions[(I)_zac.preexec]} == 0 )); then
  # Why preexec:
  # - Runs after Enter, immediately before executing the command.
  # - If USR1 arrives while the shell is idle at a prompt, preexec ensures the
  #   very next command runs with updated state (even before the next prompt).
  preexec_functions+=(_zac.preexec)
fi

TRAPUSR1() {
  # Signal handler: keep it cheap. Do not run tmux/osascript here.
  _zsh_appearance_control[needs_sync]=1
}

if [[ -n ${ZLE_STATE-} ]] && (( _zsh_appearance_control[on_source.redraw_prompt] )); then
  # If the plugin is sourced while a prompt is already displayed (ZLE active),
  # optionally load and redraw the prompt once.
  _zac._load

  if (( $+functions[_zac.sync] )); then
    # Run a sync/propagate to initialize prompt vars.
    _zsh_appearance_control[needs_sync]=1
    _zac.sync
    if (( ! _zsh_appearance_control[last_sync_changed] )); then
      _zac.propagate
    fi
  fi

  zle reset-prompt 2>/dev/null
fi
