# Ground truth selection.
#
# This function is the single place that answers: "what is dark mode right now?"
#
# Ground truth is the file $cfg.cache_dir/appearance, written by
# bin/appearance-dispatch. Reading it is a builtin read: no fork, so this is
# safe on the prompt path.
#
# tmux is never used to carry the appearance. It is only a *consumer*: the
# dispatcher writes the option @dark_appearance so the tmux status bar theme can
# restyle itself. Remote hosts get the file too, because ssh-tmux writes it at
# connect time (see src/ssh-tmux.zsh and docs/design-tmux-independence.md).
function _zac.dark_mode.query_ground_truth() {
  # Sets REPLY to 1 (dark), 0 (light), or '' (unknown, return status 1).
  local dir=${_zac[cfg.cache_dir]:-}
  local file="$dir/appearance"
  local v

  # Return the result in a shell variable
  typeset -g REPLY

  if [[ -n $dir && -f $file ]]; then
    IFS= read -r v <"$file" 2>/dev/null || v=''
    case $v in
      (1) REPLY=1; return 0 ;;
      (0) REPLY=0; return 0 ;;
    esac
  fi

  # Unknown: no file yet. The next dispatch will create it.
  _zac.debug.log "truth | unknown (no cache file)"
  REPLY=''
  return 1
}
