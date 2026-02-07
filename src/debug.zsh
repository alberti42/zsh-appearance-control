#!/usr/bin/env zsh

# Debug utilities (opt-in).
#
# Enabled by env var: ZAC_DEBUG=1 (or dynamically via `zac debug on`).
#
# Implementation notes:
# - We use a single shared FIFO per user so one monitor can observe all shells.
# - Writes to a FIFO can block if nobody is reading. To keep the prompt safe,
#   we only open the FIFO for writing in non-blocking mode; if no reader is
#   attached, logging is dropped.

function _zac.debug.ts() {
  # Format a timestamp into REPLY.
  # Uses zsh/datetime when available.
  local ts
  zmodload -F zsh/datetime b:strftime 2>/dev/null
  if (( $+functions[strftime] )); then
    strftime -s ts "%Y-%m-%dT%H:%M:%S%z" ${EPOCHSECONDS:-0} 2>/dev/null
  fi
  REPLY=${ts:-${EPOCHREALTIME:-${EPOCHSECONDS:-0}}}
}

function _zac.debug.init() {
  # Create (if needed) the shared FIFO.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  #
  # Side effects:
  # - sets _zac[debug.fifo] to FIFO path
  # - sets _zac[debug.start_ts] to the init timestamp

  (( _zac[cfg.debug_mode] )) || return 0
  if [[ -n ${_zac[debug.fifo]:-} ]]; then
    [[ -p ${_zac[debug.fifo]} ]] && return 0
    _zac[debug.fifo]=''
  fi

  local tmp=${TMPDIR:-/tmp}
  local user=${USER:-${LOGNAME:-unknown}}
  local fifo="$tmp/zac-debug.${user}.fifo"

  if [[ -e $fifo && ! -p $fifo ]]; then
    print -r -- "zac debug: path exists and is not a fifo: $fifo" >&2
    return 1
  fi

  if [[ ! -p $fifo ]]; then
    command mkfifo -m 600 -- "$fifo" 2>/dev/null || [[ -p $fifo ]] || return 1
  fi

  _zac[debug.fifo]=$fifo

  _zac.debug.ts
  _zac[debug.start_ts]=$REPLY

  # Best-effort: log an init marker if a reader is already attached.
  _zac.debug.log "zac debug init | fifo=${fifo}"
}

function _zac.debug.log() {
  # Write a log line to the FIFO.
  #
  # Usage:
  #   _zac.debug.log "message"
  (( _zac[cfg.debug_mode] )) || return 0

  local fifo=${_zac[debug.fifo]:-}
  [[ -n $fifo ]] || return 0

  local fd=${_zac[debug.fd]:-}
  if [[ -z $fd ]]; then
    # Open in non-blocking write mode. If nobody is reading, this fails.
    zmodload -F zsh/system b:sysopen 2>/dev/null || return 0
    sysopen -w -o nonblock -u fd -- "$fifo" 2>/dev/null || return 0
    _zac[debug.fd]=$fd

    # Emit a start marker when the first writer successfully connects.
    local start_ts=${_zac[debug.start_ts]:-}
    [[ -n $start_ts ]] && builtin print -r -- >&$fd "${start_ts} | zac debug start"
  fi

  _zac.debug.ts
  { builtin print -r -- >&$fd "${REPLY} | $*" } 2>/dev/null || {
    # Broken pipe / reader went away.
    exec {fd}>&-
    _zac[debug.fd]=''
  }
}

function _zac.debug.console.follow() {
  # Follow the debug FIFO and print lines to the terminal.
  # This blocks; stop with Ctrl-C.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  local fifo=${_zac[debug.fifo]:-}
  if [[ -z $fifo ]]; then
    print -r -- "zac debug console: debug fifo is not initialized" >&2
    return 1
  fi

  if [[ ! -p $fifo ]]; then
    print -r -- "zac debug console: fifo not found: $fifo" >&2
    return 1
  fi

  print -r -- "-- zac debug console | following $fifo (Ctrl-C to stop) --"

  local line
  while IFS= read -r line; do
    print -r -- "$line"
  done <"$fifo"
}

function _zac.debug.controller() {
  # Debug CLI controller.
  #
  # Usage:
  #   zac debug on|off|status|console
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  local sub=${1:-status}
  shift $(( $# > 0 ? 1 : 0 ))

  case $sub in
    (1|on|true|enable|enabled)
      _zac[cfg.debug_mode]=1
      _zac.debug.init || return $?
      return 0
    ;;

    (0|off|false|disable|disabled)
      _zac[cfg.debug_mode]=0

      local fd=${_zac[debug.fd]:-}
      if [[ -n $fd ]]; then
        exec {fd}>&-
        _zac[debug.fd]=''
      fi

      return 0
    ;;

    (status)
      local enabled=0
      (( _zac[cfg.debug_mode] )) && enabled=1

      local fifo=${_zac[debug.fifo]:-}
      local fifo_ok=0
      [[ -n $fifo && -p $fifo ]] && fifo_ok=1

      local fd_ok=0
      [[ -n ${_zac[debug.fd]:-} ]] && fd_ok=1

      print -r -- "enabled=${enabled} fifo=${fifo:-} fifo_ok=${fifo_ok} writer_fd=${fd_ok}"
      return 0
    ;;

    (console)
      # Monitor: implicitly enable debug for this shell.
      _zac[cfg.debug_mode]=1
      _zac.debug.init || return $?
      _zac.debug.console.follow
      return $?
    ;;

    (-h|--help|help)
      print -r -- "usage: zac debug <on|off|status|console>"
      return 0
    ;;
  esac

  print -r -- "zac debug: unknown subcommand: $sub" >&2
  return 2
}

function _zac.debug.module_init() {
  # Debug module init (idempotent).
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  (( ${+_zac[guard.debug_module_inited]} )) && return 0
  _zac[guard.debug_module_inited]=1

  _zac.debug.init
}

_zac.debug.module_init
