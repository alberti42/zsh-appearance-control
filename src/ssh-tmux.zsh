#!/usr/bin/env zsh

# ssh-tmux (optional extra).
#
# This command connects via SSH and hands the local appearance to the remote
# host, then attaches to a tmux session there.
#
# The appearance travels through the remote ground truth file, never through a
# tmux option: tmux is a consumer of the appearance, not a transport for it.
#
# On the remote host we prefer `appearance-dispatch`, because it also signals
# the remote shells that are already running. If it is not installed, we write
# the default cache file directly.
#
# The remote file is per user on that host, so all sessions of that user there
# share one value. That is the intended scope: one person uses one theme at a
# time.
#
# Limitation: we assume the default remote cache path, because a remote
# ZAC_CACHE_DIR is unknown to the local side.
#
# Safety:
# - We do NOT send USR1 to remote processes ourselves.
#   Signaling unknown processes is unsafe; remote shells may not have traps.

function ssh-tmux() {
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  local dark_mode
  dark_mode=$(zac status 2>/dev/null)
  case $dark_mode in
    (1) ;; 
    (*) dark_mode=0 ;;
  esac

  local session=${_zac[cfg.ssh_tmux_session]:-main}

  # Remote snippet: POSIX syntax, so it runs under any login shell.
  local remote_cmd
  remote_cmd="d=\${XDG_CACHE_HOME:-\$HOME/.cache}/zac;"
  remote_cmd+=" mkdir -p \"\$d\" && printf '%s\\n' ${dark_mode} > \"\$d/appearance\";"
  remote_cmd+=" command -v appearance-dispatch >/dev/null 2>&1 &&"
  remote_cmd+=" appearance-dispatch dispatch ${dark_mode} >/dev/null 2>&1;"
  remote_cmd+=" exec tmux new-session -A -s ${session}"

  command ssh -t "$@" "$remote_cmd"
}

# Enforce the same autocompletion for ssh-tmux as for ssh (when available).
(( ${+functions[compdef]} )) && compdef ssh-tmux=ssh

# Keep the module load status at 0: without compdef the line above returns 1,
# and _zac.module.compile_and_source would report a bogus load failure.
true
