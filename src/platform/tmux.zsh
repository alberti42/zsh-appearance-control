#!/usr/bin/env zsh

# tmux integration.
#
# The option @dark_appearance is used as the tmux-side ground truth when the
# shell runs inside tmux. An external process (e.g. WezTerm hook) is expected
# to keep this option updated when OS appearance changes.

function _zac.tmux_dark_mode.query() {
  # Query tmux option @dark_appearance.
  # Sets REPLY to 1 (dark) or 0 (light).
  [[ -n $TMUX ]] || return 1

  local v
  read -r v < <(command tmux show-options -gvq @dark_appearance 2>/dev/null)
  : ${v:=0}

  case $v in
    (1|on|true|yes) REPLY=1 ;;
    (*)             REPLY=0 ;;
  esac
}

function _zac.tmux_dark_mode.set() {
  # Set tmux option @dark_appearance.
  #
  # This is useful when the user triggers a change from inside the terminal.
  # In the preferred architecture, an external watcher updates this option.
  [[ -n $TMUX ]] || return 1
  command tmux set-option -gq @dark_appearance "$1" 2>/dev/null
}
