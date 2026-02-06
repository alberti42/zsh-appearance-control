#!/usr/bin/env zsh

###################################################
#  zsh-appearance-control (c) 2026 Andrea Alberti
###################################################

# Create an associative array to organize the variables of this zsh plugin
typeset -gA _zsh_appearance_control
_zsh_appearance_control[callback.fnc]=''
_zsh_appearance_control[dark_mode]=''
_zsh_appearance_control[needs_sync]=1
_zsh_appearance_control[needs_init_propagate]=0
_zsh_appearance_control[last_sync_changed]=0
_zsh_appearance_control[logon]=0

# propagate from _zsh_appearance_control[dark_mode] -> plugin vars
function _zac.propagate() {
  # During shell startup, let plugins initialize first.
  (( _zsh_appearance_control[logon] )) && return

  local dark_mode=${_zsh_appearance_control[dark_mode]:-0}
  
  if [[ ${(t)_zsh_opencode_tab} == association* ]]; then
    if (( dark_mode )); then
      _zsh_opencode_tab[spinner.bg_hex]="#000000"
    else
      _zsh_opencode_tab[spinner.bg_hex]="#FFFFFF"
    fi
  fi

  local cb=${_zsh_appearance_control[callback.fnc]}
  if [[ -n $cb && $+functions[$cb] -eq 1 ]]; then
    $cb $dark_mode
  fi
}

# This function returns the OS appearance as the ground truth.
# It must set REPLY to 0/1.
function _zac.get_os_appearance() {
  local dark_mode

  # If in TMUX, we use @dark_appearance as the ground truth
  if [[ -n $TMUX ]]; then
    # Read tmux option (0/1). If unset, default to 0.
    read -r dark_mode < <(tmux show-options -gvq @dark_appearance 2>/dev/null)
    : ${dark_mode:=0}
  else
    # TODO: source OS appearance outside tmux
    dark_mode=0
  fi

  # Normalize to 0/1 (tmux options may be set as on/true/yes).
  case $dark_mode in
    (1|on|true|yes) dark_mode=1 ;;
    (*)             dark_mode=0 ;;
  esac

  REPLY=$dark_mode
}

function _zac.sync() {
  local dark_mode old_mode changed=0

  _zac.get_os_appearance
  dark_mode=$REPLY
  old_mode=${_zsh_appearance_control[dark_mode]}

  if [[ $old_mode != $dark_mode ]]; then
    _zsh_appearance_control[dark_mode]=$dark_mode
    changed=1
    _zac.propagate
  fi

  _zsh_appearance_control[last_sync_changed]=$changed
  _zsh_appearance_control[needs_sync]=0
}

# Only in interactive shells
if [[ -o interactive ]]; then
  # Set shell variables for internal appearance state management
  _zsh_appearance_control[needs_sync]=1
  _zsh_appearance_control[needs_init_propagate]=0
  _zsh_appearance_control[last_sync_changed]=0
  _zsh_appearance_control[logon]=1

  # Run one sync early (initializes cache), but don't fight plugin init yet
  _zac.sync
  
  _zac.precmd() {
    # First prompt: allow plugins to finish init, then propagate once.
    if (( _zsh_appearance_control[logon] )); then
      _zsh_appearance_control[logon]=0
      _zsh_appearance_control[needs_sync]=1
      _zsh_appearance_control[needs_init_propagate]=1
    fi

    if (( _zsh_appearance_control[needs_sync] )); then
      _zac.sync
    fi

    if (( _zsh_appearance_control[needs_init_propagate] )); then
      _zsh_appearance_control[needs_init_propagate]=0
      if (( ! _zsh_appearance_control[last_sync_changed] )); then
        _zac.propagate
      fi
    fi
  }

  if (( ${precmd_functions[(I)_zac.precmd]} == 0 )); then
    precmd_functions+=(_zac.precmd)
  fi
fi

# Signal handler: avoid running tmux/ps/subprocess here. Just mark needs_sync.
TRAPUSR1() {
  _zsh_appearance_control[needs_sync]=1
}
