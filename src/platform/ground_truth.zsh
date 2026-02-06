# Queries the plugin's ground truth for dark mode.
# If in tmux, @dark_appearance is authoritative.
function _zac.dark_mode.query_ground_truth() {
  if [[ -n $TMUX ]] && _zac.tmux_dark_mode.query; then
    return 0
  fi

  _zac.os_dark_mode.query
}
