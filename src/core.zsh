# Core runtime for zsh-appearance-control.
#
# This file implements:
# - the state machine for "needs_sync" and "logon" handling
# - the sync path that reads ground truth and updates cached is_dark
# - the propagation path that updates prompt-related variables / callback
#
# This file is also self-contained:
# - it knows how to compile+source other modules in this plugin
# - it sources its hard dependencies (tmux + ground truth)
# - it self-initializes by calling _zac.init once at EOF
#
# State keys used (see also zsh-appearance-control.plugin.zsh):
# - _zsh_appearance_control[is_dark]                cached boolean (0/1)
# - _zsh_appearance_control[needs_sync]             1 => call _zac.sync soon
# - _zsh_appearance_control[logon]                  1 => avoid touching others
# - _zsh_appearance_control[needs_init_propagate]   1 => propagate once post-logon
# - _zsh_appearance_control[last_sync_changed]      1 => last sync changed is_dark
# - _zsh_appearance_control[callback.fnc]           optional function name
# - _zsh_appearance_control[on_change.redraw_prompt] if sync runs in ZLE, redraw

typeset -gA _zsh_appearance_control

function _zac.module.compile() {
  # Compile a script to a .zwc if ZAC_COMPILE=1 and the .zwc is missing/stale.
  local script=$1
  local compile=${ZAC_COMPILE:-1}

  (( compile )) || return 0
  [[ -n $script ]] || return 1

  local compiled_script="${script}.zwc"
  if [[ ! -f $compiled_script || $script -nt $compiled_script ]]; then
    if ! zcompile -Uz -- "$script" "$compiled_script" 2>/dev/null; then
      print -r -- "zac: warning: failed to compile: $script" >&2
    fi
  fi
}

function _zac.module.compile_and_source() {
  # Compile (optional) and source a plugin module by workspace-relative path.
  local module=$1

  local dir=${_zsh_appearance_control[plugin.dir]:-}
  if [[ -z $dir ]]; then
    local core_path=${${(%):-%x}:a}
    dir=${core_path:h:h}
    _zsh_appearance_control[plugin.dir]=$dir
  fi

  local script="$dir/$module"

  if [[ ! -f $script ]]; then
    print -r -- "zac: error: missing module: $script" >&2
    return 1
  fi

  _zac.module.compile "$script"

  if ! builtin source "$script"; then
    print -r -- "zac: error: failed to source: $script" >&2
    return 1
  fi
}

# Compile this core module for subsequent shells.
_zac.module.compile "${${(%):-%x}:a}"

# Source hard dependencies (idempotent).
(( $+functions[_zac.tmux_dark_mode.query] )) || _zac.module.compile_and_source src/platform/tmux.zsh
(( $+functions[_zac.dark_mode.query_ground_truth] )) || _zac.module.compile_and_source src/platform/ground_truth.zsh

function _zac.init.config() {
  # Read user configuration from env vars.
  # This is the only place that reads ZAC_* env vars.

  : ${_zsh_appearance_control[callback.fnc]:=''}
  : ${_zsh_appearance_control[callback.fnc]:=${ZAC_CALLBACK_FNC:-''}}

  : ${_zsh_appearance_control[on_source.redraw_prompt]:=${ZAC_ON_SOURCE_REDRAW_PROMPT:-0}}
  : ${_zsh_appearance_control[on_change.redraw_prompt]:=${ZAC_ON_CHANGE_REDRAW_PROMPT:-0}}

  : ${_zsh_appearance_control[debug.mode]:=${ZAC_DEBUG:-0}}
}

function _zac.init.state() {
  # Initialize internal state keys (do not read external ground truth here).

  : ${_zsh_appearance_control[is_dark]:=''}
  : ${_zsh_appearance_control[needs_sync]:=0}
  : ${_zsh_appearance_control[needs_init_propagate]:=0}
  : ${_zsh_appearance_control[last_sync_changed]:=0}
  : ${_zsh_appearance_control[logon]:=0}

  : ${_zsh_appearance_control[debug.fifo]:=''}
  : ${_zsh_appearance_control[debug.fd]:=''}
  : ${_zsh_appearance_control[debug.start_ts]:=''}
}

function _zac.init.debug() {
  # Load and initialize debug module if enabled.
  (( _zsh_appearance_control[debug.mode] )) || return 0

  if (( $+functions[_zac.debug.init] == 0 )); then
    _zac.module.compile_and_source src/debug.zsh
  fi
}

function _zac.init.shell() {
  # Per-shell startup initialization.
  #
  # Must not query external state.
  (( ${+_zsh_appearance_control[_shell_inited]} )) && return 0
  _zsh_appearance_control[_shell_inited]=1

  local in_zle=0
  [[ -n ${ZLE_STATE-} ]] && in_zle=1

  # Do not force a sync on init. Sync should be triggered explicitly (USR1 or
  # `zac sync`) to avoid prompt stalls.
  _zsh_appearance_control[needs_init_propagate]=0
  _zsh_appearance_control[last_sync_changed]=0

  if (( in_zle )); then
    # If sourced while editing a command line, allow propagation immediately.
    _zsh_appearance_control[logon]=0
  else
    # During shell startup, keep logon=1 until the first prompt.
    _zsh_appearance_control[logon]=1
  fi
}

function _zac.init() {
  # Public entry point called once from zsh-appearance-control.plugin.zsh.
  #
  # Responsibilities:
  # - Initialize config (env) + internal defaults
  # - Initialize debug (if enabled)
  # - Initialize runtime flags (logon, etc.)
  # - Register zsh integration points (hooks + TRAPUSR1)
  #
  # Non-responsibilities:
  # - No external queries (tmux/OS) and no sync.
  (( ${+_zsh_appearance_control[_inited]} )) && return 0
  _zsh_appearance_control[_inited]=1

  _zac.init.config
  _zac.init.state
  _zac.init.debug
  _zac.init.shell

  _zac.debug.log "init | begin"

  if (( ${precmd_functions[(I)_zac.precmd]} == 0 )); then
    _zac.debug.log "init | hook precmd"
    precmd_functions+=(_zac.precmd)
  fi

  if (( ${preexec_functions[(I)_zac.preexec]} == 0 )); then
    _zac.debug.log "init | hook preexec"
    preexec_functions+=(_zac.preexec)
  fi

  # Signal handler: keep it cheap. Do not run tmux/osascript here.
  TRAPUSR1() {
    _zsh_appearance_control[needs_sync]=1
  }

  if [[ -n ${ZLE_STATE-} ]] && (( _zsh_appearance_control[on_source.redraw_prompt] )); then
    _zac.debug.log "init | redraw on source"
    _zac.propagate
    zle reset-prompt 2>/dev/null
  fi

  _zac.debug.log "init | done"
}

# Propagate from _zsh_appearance_control[is_dark] -> plugin vars.
function _zac.propagate() {
  # Apply cached state to prompt-related variables.
  #
  # This function must be fast and side-effect-safe because it can be called
  # from hooks. It does not query tmux/OS.
  (( _zsh_appearance_control[logon] )) && return

  _zac.debug.log "core | propagate | is_dark=${_zsh_appearance_control[is_dark]:-}"

  local cb=${_zsh_appearance_control[callback.fnc]}
  if [[ -n $cb && $+functions[$cb] -eq 1 ]]; then
    local is_dark=${_zsh_appearance_control[is_dark]:-0}
    
    $cb $is_dark
  fi
}

function _zac.sync() {
  # Sync cached is_dark with the external ground truth.
  #
  # Ground truth is queried via _zac.dark_mode.query_ground_truth (platform).
  # If the value changes, we update the cache and call _zac.propagate.
  local is_dark old_mode changed=0

  _zac.debug.log "core | sync | start"
  _zac.dark_mode.query_ground_truth
  is_dark=$REPLY

  _zac.debug.log "core | sync | ground_truth=${is_dark}"

  old_mode=${_zsh_appearance_control[is_dark]}
  if [[ $old_mode != $is_dark ]]; then
    _zsh_appearance_control[is_dark]=$is_dark
    changed=1
    _zac.propagate
  fi

  _zac.debug.log "core | sync | changed=${changed}"

  _zsh_appearance_control[last_sync_changed]=$changed
  _zsh_appearance_control[needs_sync]=0

  if (( changed )) && (( _zsh_appearance_control[on_change.redraw_prompt] )) && [[ -n ${ZLE_STATE-} ]]; then
    # Only meaningful if a sync happens while ZLE is active.
    zle reset-prompt 2>/dev/null
  fi
}

function _zac.precmd() {
  # precmd hook: runs right before the prompt is shown.
  # Used to perform deferred sync work and to perform one-time post-logon
  # propagation.
  if (( _zsh_appearance_control[logon] )); then
    _zac.debug.log "core | precmd | first prompt"
    _zsh_appearance_control[logon]=0
    _zsh_appearance_control[needs_init_propagate]=1
  fi

  if (( _zsh_appearance_control[needs_sync] )); then
    _zac.debug.log "core | precmd | needs_sync=1"
    _zac.sync
  fi

  if (( _zsh_appearance_control[needs_init_propagate] )); then
    _zsh_appearance_control[needs_init_propagate]=0
    if (( ! _zsh_appearance_control[last_sync_changed] )); then
      # Ensure prompt-dependent vars are initialized even if the first sync did
      # not change the cached value.
      _zac.propagate
    fi
  fi
}

function _zac.preexec() {
  # preexec hook: runs after Enter, right before executing the command.
  # This helps keep state correct even if a signal arrived while the user was
  # sitting at a prompt (no precmd ran yet).
  if (( _zsh_appearance_control[needs_sync] )); then
    _zac.debug.log "core | preexec | needs_sync=1"
    _zac.sync
  fi
}

# Self-init when sourced.
_zac.init
