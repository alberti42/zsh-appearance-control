# Ground truth selection.
#
# This function is the single place that answers: "what is dark mode right now?"
#
# Ground truth is the file $cfg.cache_dir/appearance, written by
# bin/appearance-dispatch. Reading it is a builtin read: no fork, so this is
# safe on the prompt path.
#
# tmux is a *consumer* of the appearance (the status bar theme reads the option
# @dark_appearance), not its source. The only case where the option is still
# read is a remote host reached with ssh-tmux: there nothing writes the file,
# and the option carries the appearance of the local machine. That fallback
# disappears once docs/design-tmux-independence.md is implemented.
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

  # Fallback: no file, so we may be on a remote host inside tmux.
  # The module is loaded on demand, to keep it off the startup path.
  if [[ -n $TMUX ]]; then
    _zac.debug.log "truth | tmux fallback (no cache file)"
    (( $+functions[_zac.tmux_dark_mode.query] )) ||
      _zac.module.compile_and_source src/platform/tmux.zsh || return 1
    _zac.tmux_dark_mode.query
    return $?
  fi

  # Unknown.
  REPLY=''
  return 1
}
