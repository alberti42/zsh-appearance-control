function _zac.tmux_dark_mode.query() {
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
  [[ -n $TMUX ]] || return 1
  command tmux set-option -gq @dark_appearance "$1" 2>/dev/null
}
