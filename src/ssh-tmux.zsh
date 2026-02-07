#!/usr/bin/env zsh

# ssh-tmux (optional extra).
#
# This command connects via SSH and ensures the remote tmux session has the
# @dark_appearance option set to the current local appearance.
#
# Safety:
# - We do NOT send USR1 to remote processes.
#   Signaling unknown processes is unsafe; remote shells may not have traps.

function ssh-tmux() {
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  local dark_mode
  dark_mode=$(zac status 2>/dev/null)
  case $dark_mode in
    (1) ;; 
    (*) dark_mode=0 ;;
  esac

  # Pass the appearance to the remote tmux session.
  # Note: use `\\;` so the remote shell receives a literal `\;`.
  command ssh -t "$@" "tmux new-session -A -s main \\; set-option -gq @dark_appearance ${dark_mode}"
}

# Enforce the same autocompletion for ssh-tmux as for ssh (when available).
(( ${+functions[compdef]} )) && compdef ssh-tmux=ssh
