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

  # TODO: non-tmux ground truth (e.g. file-based state).
  # For now, fall back to the current cached value.
  _zac.debug.log "truth | non-tmux TODO (using cache)"
  REPLY=${_zac[state.is_dark]:-0}
  return 0
}
