# Ground truth selection.
#
# This function is the single place that answers: "what is dark mode right now?"
#
# For now:
# - If running inside tmux, tmux option @dark_appearance is authoritative.
# - Outside tmux: TODO. We do NOT query the OS yet; we return the cached value.
function _zac.dark_mode.query_ground_truth() {
  # Sets REPLY to 1 (dark) or 0 (light).
  if [[ -n $TMUX ]]; then
    _zac.debug.log "truth | tmux"
    _zac.tmux_dark_mode.query
    return $?
  fi

  # Non-tmux ground truth: file-based state in cfg.cache_dir.
  local dir=${_zac[cfg.cache_dir]:-}
  local file="$dir/appearance"
  local v

  if [[ -n $dir && -f $file ]]; then
    IFS= read -r v <"$file" 2>/dev/null || v=''
    case $v in
      (1) REPLY=1; return 0 ;;
      (0) REPLY=0; return 0 ;;
    esac
  fi

  # Unknown.
  REPLY=''
  return 1
}
