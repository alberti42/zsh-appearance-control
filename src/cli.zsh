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
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  _zac.debug.log "cli | zac $*"
  local cmd=${1:-status}
  shift $(( $# > 0 ? 1 : 0 ))

  case $cmd in
    (-h|--help|help)
      print -r -- "usage: zac <status|sync|toggle|dark|light|debug>"
      return 0
    ;;

    (status)
      # Print cached state only; does not query OS/tmux.
      #
      # Contract:
      # - Always prints 1 (dark) or 0 (light/unknown fallback)
      # - Returns 0 when known, 1 when unknown
      if (( ${+_zac[state.is_dark]} )) && [[ -n ${_zac[state.is_dark]} ]]; then
        print -r -- ${_zac[state.is_dark]}
        return 0
      fi

      print -r -- 0
      return 1
    ;;

    (sync)
      # Force a sync from ground truth.
      _zac.debug.log "cli | sync"
      _zac[state.needs_sync]=1
      _zac.sync
      local rc=$?
      if (( rc == 0 )) && (( _zac[state.needs_propagate] )); then
        _zac.propagate
      fi
      return $rc
    ;;

    (debug)
      # Debug controller (lazy-loaded).
      _zac.debug.controller "$@"
      return $?
    ;;

    (toggle|dark|light)
      # Set dark mode via OS integration and update cached state optimistically.
      _zac.debug.log "cli | set $cmd"
      local target

      if [[ $cmd == toggle ]]; then
        # Toggle based on cached state only (avoid querying ground truth).
        local cur=${_zac[state.is_dark]:-0}
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
      _zac[state.is_dark]=$target
      _zac.propagate
      # Do not schedule a sync here; external mechanism will send USR1.
      _zac[state.needs_sync]=0
      return 0
    ;;
  esac

  print -r -- "zac: unknown command: $cmd" >&2
  return 2
}

function _zac.cli.init() {
  # CLI module init (idempotent).
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  (( ${+_zac[guard.cli_inited]} )) && return 0
  _zac[guard.cli_inited]=1
}

_zac.cli.init
