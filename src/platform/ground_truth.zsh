# Queries the plugin's ground truth for dark mode.
# If in tmux, @dark_appearance is authoritative.
function _zac.dark_mode.query_ground_truth() {
  if [[ -n $TMUX ]]; then
    _zac.tmux_dark_mode.query
    return $?
  fi

  # TODO: non-tmux ground truth (e.g. file-based state).
  # For now, fall back to the current cached value.
  REPLY=${_zsh_appearance_control[is_dark]:-0}
  return 0
}
