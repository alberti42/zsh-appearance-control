# User command entrypoint.

function zac() {
  local cmd=${1:-status}
  shift $(( $# > 0 ? 1 : 0 ))

  case $cmd in
    (-h|--help|help)
      print -r -- "usage: zac <status|sync|toggle|dark|light>"
      return 0
    ;;

    (status)
      if (( ${+_zsh_appearance_control[is_dark]} )) && [[ -n ${_zsh_appearance_control[is_dark]} ]]; then
        (( _zsh_appearance_control[is_dark] )) && print -r -- dark || print -r -- light
      else
        print -r -- unknown
      fi
      return 0
    ;;

    (sync)
      _zsh_appearance_control[needs_sync]=1
      _zac.sync
      return $?
    ;;

    (toggle|dark|light)
      local target

      if [[ $cmd == toggle ]]; then
        _zac.dark_mode.query_ground_truth
        target=$(( REPLY ? 0 : 1 ))
      elif [[ $cmd == dark ]]; then
        target=1
      else
        target=0
      fi

      if [[ -n $TMUX ]]; then
        _zac.tmux_dark_mode.set $target
      fi

      if ! _zac.os_dark_mode.set $target; then
        print -r -- "zac: unsupported platform ($OSTYPE)" >&2
        return 1
      fi

      _zsh_appearance_control[needs_sync]=1
      _zac.sync
      return 0
    ;;
  esac

  print -r -- "zac: unknown command: $cmd" >&2
  return 2
}
