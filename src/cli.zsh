# User command entrypoint.

function zac() {
  local cmd=${1:-status}
  shift $(( $# > 0 ? 1 : 0 ))

  case $cmd in
    (-h|--help|help)
      print -r -- "usage: zac <status|sync|toggle|dark|light|callback>"
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

    (callback)
      if (( $# == 0 )); then
        local cb=${_zsh_appearance_control[callback.fnc]:-}
        if [[ -n $cb ]]; then
          print -r -- "$cb"
        else
          print -r -- "--no callback function set--"
        fi
        return 0
      fi

      if [[ $1 == '-' ]]; then
        _zsh_appearance_control[callback.fnc]=''
        return 0
      fi

      _zsh_appearance_control[callback.fnc]="$1"
      return 0
    ;;

    (toggle|dark|light)
      local target

      if [[ $cmd == toggle ]]; then
        local cur=${_zsh_appearance_control[is_dark]:-0}
        target=$(( cur ? 0 : 1 ))
      elif [[ $cmd == dark ]]; then
        target=1
      else
        target=0
      fi

      if ! _zac.os_dark_mode.set $target; then
        print -r -- "zac: unsupported platform ($OSTYPE)" >&2
        return 1
      fi

      # Trust the transition; update cache and prompt immediately.
      _zsh_appearance_control[is_dark]=$target
      _zac.propagate
      _zsh_appearance_control[needs_sync]=0
      return 0
    ;;
  esac

  print -r -- "zac: unknown command: $cmd" >&2
  return 2
}
