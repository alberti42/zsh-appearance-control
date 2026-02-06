# User command entrypoint.
#
# The `zac` function is intentionally simple:
# - `zac dark|light|toggle` sets macOS dark mode (async) and immediately updates
#   the plugin's cached state + propagates prompt variables.
# - It does NOT perform a ground-truth query after setting (avoids prompt stalls).
# - External changes should be communicated via USR1 (TRAPUSR1 sets needs_sync=1).
# - `zac sync` forces a sync from ground truth (tmux @dark_appearance for now).

function zac() {
  # CLI dispatcher.
  _zac.debug.log "cli | zac $*"
  local cmd=${1:-status}
  shift $(( $# > 0 ? 1 : 0 ))

  case $cmd in
    (-h|--help|help)
      print -r -- "usage: zac <status|sync|toggle|dark|light|callback>"
      return 0
    ;;

    (status)
      # Print cached state only; does not query OS/tmux.
      if (( ${+_zsh_appearance_control[is_dark]} )) && [[ -n ${_zsh_appearance_control[is_dark]} ]]; then
        (( _zsh_appearance_control[is_dark] )) && print -r -- dark || print -r -- light
      else
        print -r -- unknown
      fi
      return 0
    ;;

    (sync)
      # Force a sync from ground truth.
      _zac.debug.log "cli | sync"
      _zsh_appearance_control[needs_sync]=1
      _zac.sync
      return $?
    ;;

    (callback)
      # Get/set the callback function name.
      # The callback is called by _zac.propagate as: $callback <is_dark>.
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
        # Disable callback.
        _zsh_appearance_control[callback.fnc]=''
        return 0
      fi

      _zsh_appearance_control[callback.fnc]="$1"
      return 0
    ;;

    (toggle|dark|light)
      # Set dark mode via OS integration and update cached state optimistically.
      _zac.debug.log "cli | set $cmd"
      local target

      if [[ $cmd == toggle ]]; then
        # Toggle based on cached state only (avoid querying ground truth).
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
      # Do not schedule a sync here; external mechanism will send USR1.
      _zsh_appearance_control[needs_sync]=0
      return 0
    ;;
  esac

  print -r -- "zac: unknown command: $cmd" >&2
  return 2
}

function _zac.cli.init() {
  # CLI module init (idempotent).
  (( ${+_zsh_appearance_control[_cli_inited]} )) && return 0
  _zsh_appearance_control[_cli_inited]=1
}

_zac.cli.init
