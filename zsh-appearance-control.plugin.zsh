#!/usr/bin/env zsh

###################################################
#  zsh-appearance-control (c) 2026 Andrea Alberti
###################################################

# Create an associative array to organize the variables of this zsh plugin
typeset -gA _zsh_appearance_control
_zsh_appearance_control[callback.fnc]=''

# propagate from DARK_APPEARANCE -> plugin vars
function __my_appearance_propagate() {
  # During shell startup, let plugins initialize first.
  (( _APPEARANCE_LOGON )) && return 
  
  if (( DARK_APPEARANCE )); then
    _zsh_opencode_tab[spinner.bg_hex]="#000000"
  else
    _zsh_opencode_tab[spinner.bg_hex]="#FFFFFF"
  fi
}

function __my_appearance_apply() {
  local dark_mode

  # If in TMUX, we use @dark_appearance as the ground truth
  if [[ -n $TMUX ]]; then
    # Read tmux option (0/1). If unset, default to 0.
    read -r dark_mode < <(tmux show-options -gvq @dark_appearance 2>/dev/null)
    : ${dark_mode:=0}
  else
    # Fallback outside tmux (use env if present, else default 0)
    dark_mode=${DARK_APPEARANCE:-0}
  fi

  # Only update env if highlighting changed
  if [[ ${DARK_APPEARANCE:-} != $dark_mode ]]; then
    export DARK_APPEARANCE=$dark_mode
    __my_appearance_propagate
  fi

  _APPEARANCE_DIRTY=0
}

# Only in interactive shells
if [[ -o interactive ]]; then
  # Set shell variables for internal appearance state management
  typeset -g _APPEARANCE_DIRTY=1
  typeset -g _APPEARANCE_LOGON=1

  # Run one sync early (sets DARK_APPEARANCE), but don't fight plugin init yet
  __my_appearance_apply
  
  __my_appearance_precmd() {
    # First prompt: allow plugins to finish init, then propagate once
    if (( _APPEARANCE_LOGON )); then
      _APPEARANCE_LOGON=0
      _APPEARANCE_DIRTY=1
    fi

    if (( _APPEARANCE_DIRTY )); then
      __my_appearance_apply
    fi
  }

  precmd_functions+=(__my_appearance_precmd)  
fi

# Signal handler: avoid running tmux/ps/subprocess here. Just mark dirty.
TRAPUSR1() {
  _APPEARANCE_DIRTY=1
}
