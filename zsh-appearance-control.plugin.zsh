#!/usr/bin/env zsh

###################################################
#  zsh-appearance-control (c) 2026 Andrea Alberti
###################################################

# Prompt/plugin behavior only: do nothing in non-interactive shells.
[[ -o interactive ]] || return 0

# Create an associative array to organize the variables of this zsh plugin
typeset -gA _zsh_appearance_control
_zsh_appearance_control[callback.fnc]=''
_zsh_appearance_control[dark_mode]=''
_zsh_appearance_control[needs_sync]=1
_zsh_appearance_control[needs_init_propagate]=0
_zsh_appearance_control[last_sync_changed]=0
_zsh_appearance_control[logon]=0
_zsh_appearance_control[on_source.redraw_prompt]=${ZAC_ON_SOURCE_REDRAW_PROMPT:-0}
_zsh_appearance_control[on_change.redraw_prompt]=${ZAC_ON_CHANGE_REDRAW_PROMPT:-0}

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
    read -r dark_mode < <(command tmux show-options -gvq @dark_appearance 2>/dev/null)
    : ${dark_mode:=0}
  else
    case $OSTYPE in
      (darwin*)
        dark_mode=$(command osascript 2>/dev/null <<'OSA'
tell application "System Events"
	tell appearance preferences
		get dark mode
	end tell
end tell
OSA
        )
        [[ $dark_mode == true ]] && dark_mode=1 || dark_mode=0
      ;;
      (*)
        dark_mode=0
      ;;
    esac
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

  if (( changed )) && (( _zsh_appearance_control[on_change.redraw_prompt] )) && [[ -n ${ZLE_STATE-} ]]; then
    zle reset-prompt 2>/dev/null
  fi
}

function _zac._set_os_appearance() {
  local target=$1

  case $OSTYPE in
    (darwin*)
      if (( target )); then
        command osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events"
	tell appearance preferences
		set dark mode to true
	end tell
end tell
OSA
      else
        command osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events"
	tell appearance preferences
		set dark mode to false
	end tell
end tell
OSA
      fi
    ;;
    (*)
      return 1
    ;;
  esac
}

function _zac._tmux_set_dark_mode() {
  [[ -n $TMUX ]] || return 1
  command tmux set-option -gq @dark_appearance "$1" 2>/dev/null
}

function zac() {
  local cmd=${1:-status}
  shift $(( $# > 0 ? 1 : 0 ))

  case $cmd in
    (-h|--help|help)
      print -r -- "usage: zac <status|sync|toggle|dark|light>"
      return 0
    ;;

    (status)
      if (( ${+_zsh_appearance_control[dark_mode]} )) && [[ -n ${_zsh_appearance_control[dark_mode]} ]]; then
        (( _zsh_appearance_control[dark_mode] )) && print -r -- dark || print -r -- light
      else
        print -r -- unknown
      fi
      return 0
    ;;

    (sync)
      _zsh_appearance_control[needs_sync]=1
      _zac.sync
      return $?
    ;;

    (toggle|dark|light)
      local target

      if [[ $cmd == toggle ]]; then
        _zac.get_os_appearance
        target=$(( REPLY ? 0 : 1 ))
      elif [[ $cmd == dark ]]; then
        target=1
      else
        target=0
      fi

      if [[ -n $TMUX ]]; then
        _zac._tmux_set_dark_mode $target
      fi

      if ! _zac._set_os_appearance $target; then
        print -r -- "zac: unsupported platform ($OSTYPE)" >&2
        return 1
      fi

      _zsh_appearance_control[needs_sync]=1
      _zac.sync
      (( target )) && print -r -- dark || print -r -- light
      return 0
    ;;
  esac

  print -r -- "zac: unknown command: $cmd" >&2
  return 2
}

local _zac_in_zle=0
[[ -n ${ZLE_STATE-} ]] && _zac_in_zle=1

# Set shell variables for internal appearance state management
_zsh_appearance_control[needs_sync]=1
_zsh_appearance_control[needs_init_propagate]=0
_zsh_appearance_control[last_sync_changed]=0
if (( _zac_in_zle )); then
  _zsh_appearance_control[logon]=0
else
  _zsh_appearance_control[logon]=1
fi

# Run one sync early (initializes cache), but don't fight plugin init yet
_zac.sync

if (( _zac_in_zle )) && (( _zsh_appearance_control[on_source.redraw_prompt] )); then
  # If sourced while already at a prompt, ensure prompt-dependent vars are
  # applied immediately and redraw without waiting for Enter.
  if (( ! _zsh_appearance_control[last_sync_changed] )); then
    _zac.propagate
  fi
  zle reset-prompt 2>/dev/null
fi

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

_zac.preexec() {
  if (( _zsh_appearance_control[needs_sync] )); then
    _zac.sync
  fi
}

if (( ${preexec_functions[(I)_zac.preexec]} == 0 )); then
  preexec_functions+=(_zac.preexec)
fi

# Signal handler: avoid running tmux/ps/subprocess here. Just mark needs_sync.
TRAPUSR1() {
  _zsh_appearance_control[needs_sync]=1
}
