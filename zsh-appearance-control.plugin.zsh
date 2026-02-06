#!/usr/bin/env zsh

###################################################
#  zsh-appearance-control (c) 2026 Andrea Alberti
###################################################

# Prompt/plugin behavior only: do nothing in non-interactive shells.
[[ -o interactive ]] || return 0

typeset -gA _zsh_appearance_control

_zsh_appearance_control[dir]=${${(%):-%x}:a:h}

: ${_zsh_appearance_control[callback.fnc]:=''}
: ${_zsh_appearance_control[callback.fnc]:=${ZAC_CALLBACK_FNC:-''}}
: ${_zsh_appearance_control[is_dark]:=''}
: ${_zsh_appearance_control[needs_sync]:=1}
: ${_zsh_appearance_control[needs_init_propagate]:=0}
: ${_zsh_appearance_control[last_sync_changed]:=0}
: ${_zsh_appearance_control[logon]:=0}

: ${_zsh_appearance_control[on_source.redraw_prompt]:=${ZAC_ON_SOURCE_REDRAW_PROMPT:-0}}
: ${_zsh_appearance_control[on_change.redraw_prompt]:=${ZAC_ON_CHANGE_REDRAW_PROMPT:-0}}

function _zac._load() {
  (( ${+_zsh_appearance_control[_loaded]} )) && return 0
  _zsh_appearance_control[_loaded]=1

  local dir=${_zsh_appearance_control[dir]}
  local compile=${ZAC_COMPILE:-1}

  local -a modules
  modules=(
    src/core.zsh
    src/platform/tmux.zsh
  )

  case $OSTYPE in
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
  _zac._load || return $?
  zac "$@"
}

function _zac.precmd() {
  _zac._load || return $?
  _zac.precmd "$@"
}

function _zac.preexec() {
  _zac._load || return $?
  _zac.preexec "$@"
}

if (( ${precmd_functions[(I)_zac.precmd]} == 0 )); then
  precmd_functions+=(_zac.precmd)
fi

if (( ${preexec_functions[(I)_zac.preexec]} == 0 )); then
  preexec_functions+=(_zac.preexec)
fi

TRAPUSR1() {
  _zsh_appearance_control[needs_sync]=1
}

if [[ -n ${ZLE_STATE-} ]] && (( _zsh_appearance_control[on_source.redraw_prompt] )); then
  _zac._load

  if (( $+functions[_zac.sync] )); then
    _zsh_appearance_control[needs_sync]=1
    _zac.sync
    if (( ! _zsh_appearance_control[last_sync_changed] )); then
      _zac.propagate
    fi
  fi

  zle reset-prompt 2>/dev/null
fi
