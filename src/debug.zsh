#!/usr/bin/env zsh

# Debug utilities (opt-in).
#
# Enabled by env var: ZAC_DEBUG=1.
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
  #
  # Side effects:
  # - sets _zsh_appearance_control[debug.fifo] to FIFO path
  # - sets _zsh_appearance_control[debug.start_ts] to the init timestamp

  (( _zsh_appearance_control[debug.mode] )) || return 0
  [[ -n ${_zsh_appearance_control[debug.fifo]:-} ]] && return 0

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

  _zsh_appearance_control[debug.fifo]=$fifo

  _zac.debug.ts
  _zsh_appearance_control[debug.start_ts]=$REPLY

  # Best-effort: log an init marker if a reader is already attached.
  _zac.debug.log "zac debug init | fifo=${fifo}"
}

function _zac.debug.log() {
  # Write a log line to the FIFO.
  #
  # Usage:
  #   _zac.debug.log "message"
  (( _zsh_appearance_control[debug.mode] )) || return 0

  local fifo=${_zsh_appearance_control[debug.fifo]:-}
  [[ -n $fifo ]] || return 0

  local fd=${_zsh_appearance_control[debug.fd]:-}
  if [[ -z $fd ]]; then
    # Open in non-blocking write mode. If nobody is reading, this fails.
    zmodload -F zsh/system b:sysopen 2>/dev/null || return 0
    sysopen -w -o nonblock -u fd -- "$fifo" 2>/dev/null || return 0
    _zsh_appearance_control[debug.fd]=$fd

    # Emit a start marker when the first writer successfully connects.
    local start_ts=${_zsh_appearance_control[debug.start_ts]:-}
    [[ -n $start_ts ]] && builtin print -r -- >&$fd "${start_ts} | zac debug start"
  fi

  _zac.debug.ts
  { builtin print -r -- >&$fd "${REPLY} | $*" } 2>/dev/null || {
    # Broken pipe / reader went away.
    exec {fd}>&-
    _zsh_appearance_control[debug.fd]=''
  }
}

function zac.debug.follow() {
  # Follow the debug FIFO and print lines to the terminal.
  # This blocks; stop with Ctrl-C.
  local fifo=${_zsh_appearance_control[debug.fifo]:-}
  if [[ -z $fifo ]]; then
    print -r -- "zac.debug.follow: debug is not enabled (set ZAC_DEBUG=1 and re-source)" >&2
    return 1
  fi

  if [[ ! -p $fifo ]]; then
    print -r -- "zac.debug.follow: fifo not found: $fifo" >&2
    return 1
  fi

  print -r -- "-- following $fifo (Ctrl-C to stop) --"

  local line
  while IFS= read -r line; do
    print -r -- "$line"
  done <"$fifo"
}

function _zac.debug.module_init() {
  # Debug module init (idempotent).
  (( ${+_zsh_appearance_control[_debug_module_inited]} )) && return 0
  _zsh_appearance_control[_debug_module_inited]=1

  _zac.debug.init
}

_zac.debug.module_init
