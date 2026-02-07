# Core runtime for zsh-appearance-control.
#
# This file implements:
# - the state machine for "needs_sync" and deferred propagation
# - the sync path that reads ground truth and updates cached is_dark
# - the propagation path that updates prompt-related variables / callback
#
# This file is also self-contained:
# - it knows how to compile+source other modules in this plugin
# - it sources its hard dependencies (tmux + ground truth)
# - it self-initializes by calling _zac.init once at EOF
#
####################################################################
# State
#
# State is stored in the global associative array:
#   _zac[...]
####################################################################

typeset -gA _zac

# zsh conventional return channels.
#
# We predeclare these so functions that intentionally set REPLY/reply do not
# trigger `warn_create_global` warnings.
typeset -g REPLY
typeset -ga reply

# Debug CLI controller stub.
#
# The debug module is optional and is only eager-loaded when ZAC_DEBUG=1.
# However, the user-facing `zac debug ...` command should work even when debug
# is disabled by default.
function _zac.debug.controller() {
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  _zac.module.compile_and_source src/debug.zsh || return $?
  _zac.debug.controller "$@"
}

function _zac.module.compile() {
  # Compile a script to a .zwc if ZAC_COMPILE=1 and the .zwc is missing/stale.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

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
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  local module=$1

  local dir=${_zac[meta.plugin_dir]:-}
  if [[ -z $dir ]]; then
    print -r -- "zac: error: meta.plugin_dir is not set" >&2
    return 1
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
_zac.module.compile "${_zac[meta.plugin_dir]}/src/core.zsh"

# Source hard dependencies (idempotent).
(( $+functions[_zac.tmux_dark_mode.query] )) || _zac.module.compile_and_source src/platform/tmux.zsh
(( $+functions[_zac.dark_mode.query_ground_truth] )) || _zac.module.compile_and_source src/platform/ground_truth.zsh

function _zac.init.config() {
  # Read user configuration from env vars.
  # This is the only place that reads ZAC_* env vars.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  # callback.fnc: optional function name called as: $callback <is_dark>
  : ${_zac[cfg.callback_fnc]:=''}
  : ${_zac[cfg.callback_fnc]:=${ZAC_CALLBACK_FNC:-''}}

  # debug.mode: enable debug FIFO logging.
  : ${_zac[cfg.debug_mode]:=${ZAC_DEBUG:-0}}

  # enable_ssh_tmux: optionally install the ssh-tmux lazy stub.
  : ${_zac[cfg.enable_ssh_tmux]:=${ZAC_ENABLE_SSH_TMUX:-1}}

  # ssh_tmux.session: remote tmux session name used by ssh-tmux.
  : ${_zac[cfg.ssh_tmux_session]:=${ZAC_SSH_TMUX_SESSION:-main}}

  # linux.desktop: enable desktop-specific OS setters on Linux.
  #
  # Values:
  # - gnome: enable GNOME integration (gsettings)
  # - none:  disable desktop integration even if auto-detected
  # - empty: auto-detect via XDG_CURRENT_DESKTOP
  local linux_desktop=${ZAC_LINUX_DESKTOP:-''}
  case $linux_desktop in
    (none) linux_desktop='' ;;
    (gnome) ;; 
    ('')
      if [[ ${XDG_CURRENT_DESKTOP-} == *GNOME* ]]; then
        linux_desktop=gnome
      fi
    ;;
    (*)
      # Unknown value: treat as disabled.
      linux_desktop=''
    ;;
  esac
  : ${_zac[cfg.linux_desktop]:=$linux_desktop}

  # cache.dir: base directory for non-tmux ground truth and pid registry.
  # Defaults to XDG cache dir when available.
  local cache_base
  cache_base=${ZAC_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/zac}
  : ${_zac[cfg.cache_dir]:=$cache_base}
}

function _zac.init.state() {
  # Initialize internal state keys (do not read external ground truth here).
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  # is_dark: cached boolean (0/1). May be empty until first sync or zac command.
  : ${_zac[state.is_dark]:=''}

  # needs_sync: 1 => hooks call _zac.sync at the next opportunity.
  : ${_zac[state.needs_sync]:=0}

  # needs_propagate: 1 => run _zac.propagate at the next safe opportunity.
  # Set by _zac.sync (when is_dark changes) and by the first prompt after load.
  : ${_zac[state.needs_propagate]:=0}

  # defer_propagate: while 1, _zac.propagate is a no-op.
  #
  # We defer propagation until the first prompt after plugin load to avoid:
  # - fighting other plugins/themes during their startup
  # - calling user callbacks before their dependencies exist
  : ${_zac[state.defer_propagate]:=0}

  # debug.fifo: shared FIFO path used by the debug module.
  : ${_zac[debug.fifo]:=''}

  # debug.fd: per-shell FD used for non-blocking debug writes.
  : ${_zac[debug.fd]:=''}

  # debug.start_ts: timestamp captured when debug module is initialized.
  : ${_zac[debug.start_ts]:=''}

  # guard.trapusr1_wrapped: 1 if we installed a chained TRAPUSR1 handler.
  : ${_zac[guard.trapusr1_wrapped]:=0}

  # guard.cache_inited: 1 once cache dirs + pid hooks are initialized.
  : ${_zac[guard.cache_inited]:=0}
}

function _zac.cache.pid.register() {
  # Register this shell PID for safe external signaling.
  #
  # This creates a file in: $cfg.cache_dir/pids/$$
  # The file contains the process start time as epoch seconds to avoid PID
  # reuse hazards.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops
  builtin setopt extended_glob

  local dir=${_zac[cfg.cache_dir]:-}
  [[ -n $dir ]] || return 0

  local pids_dir="$dir/pids"
  command mkdir -p -- "$pids_dir" 2>/dev/null || return 0
  command chmod 700 -- "$dir" "$pids_dir" 2>/dev/null || true

  local start_epoch
  start_epoch=$(_zac.cache.pid.start_epoch $$) || return 0

  local pid_file="$pids_dir/$$"
  umask 077
  builtin print -r -- "$start_epoch" >| "$pid_file" 2>/dev/null || true
}

function _zac.cache.pid.start_epoch() {
  # Print process start time as epoch seconds.
  #
  # This is used to avoid PID reuse hazards when externally signaling shells.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops
  builtin setopt extended_glob

  local pid=$1
  [[ $pid == <-> ]] || return 1

  local lstart
  lstart=$(LC_ALL=C LANG=C command ps -p "$pid" -o lstart= 2>/dev/null) || return 1
  lstart=${lstart##[[:space:]]##}
  lstart=${lstart%%[[:space:]]##}
  [[ -n $lstart ]] || return 1

  local start_epoch
  case $OSTYPE in
    (darwin*) start_epoch=$(LC_ALL=C LANG=C command date -j -f "%a %b %e %T %Y" "$lstart" +%s 2>/dev/null) ;;
    (linux*)  start_epoch=$(LC_ALL=C LANG=C command date -d "$lstart" +%s 2>/dev/null) ;;
    (*)       return 1 ;;
  esac

  [[ $start_epoch == <-> ]] || return 1
  builtin print -r -- "$start_epoch"
}

function _zac.cache.pid.unregister() {
  # Best-effort: remove this shell's pid registration.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  local dir=${_zac[cfg.cache_dir]:-}
  [[ -n $dir ]] || return 0

  command rm -f -- "$dir/pids/$$" 2>/dev/null || true
}

function _zac.cache.init() {
  # Initialize cache dirs and pid lifecycle hooks.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  (( _zac[guard.cache_inited] )) && return 0
  _zac[guard.cache_inited]=1

  local dir=${_zac[cfg.cache_dir]:-}
  [[ -n $dir ]] || return 0

  _zac.cache.pid.register

  # zshexit_functions is a special global hook array.
  if (( ${zshexit_functions[(I)_zac.cache.pid.unregister]-0} == 0 )); then
    zshexit_functions+=(_zac.cache.pid.unregister)
  fi
}

function _zac.init.debug() {
  # Load and initialize debug module if enabled.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  (( _zac[cfg.debug_mode] )) || return 0

  if (( $+functions[_zac.debug.init] == 0 )); then
    _zac.module.compile_and_source src/debug.zsh
  fi
}

function _zac.init.shell() {
  # Per-shell initialization.
  #
  # Must not query external state.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  (( ${+_zac[guard.shell_inited]} )) && return 0
  _zac[guard.shell_inited]=1

  # Do not force a sync on init. Sync should be triggered explicitly (USR1 or
  # `zac sync`) to avoid prompt stalls.
  _zac[state.needs_propagate]=0

  # Defer propagation until the next prompt after plugin load.
  #
  # This avoids fighting other plugins/themes during startup and avoids calling
  # user callbacks before their dependencies exist.
  _zac[state.defer_propagate]=1
}

function _zac.init() {
  # Public entry point called once from zsh-appearance-control.plugin.zsh.
  #
  # Responsibilities:
  # - Initialize config (env) + internal defaults
  # - Initialize debug (if enabled)
  # - Initialize runtime flags (defer_propagate, etc.)
  # - Register zsh integration points (hooks + TRAPUSR1)
  #
  # Non-responsibilities:
  # - No external queries (tmux/OS) and no sync.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  # These are special global hook arrays in zsh.
  # Declare them explicitly to avoid `warn_create_global` noise.
  typeset -ga precmd_functions preexec_functions zshexit_functions

  (( ${+_zac[guard.core_inited]} )) && return 0
  _zac[guard.core_inited]=1

  _zac.init.config
  _zac.init.state
  _zac.init.debug
  _zac.init.shell
  _zac.cache.init

  _zac.debug.log "init | begin"

  if (( ${precmd_functions[(I)_zac.precmd]-0} == 0 )); then
    _zac.debug.log "init | hook precmd"
    precmd_functions+=(_zac.precmd)
  fi

  if (( ${preexec_functions[(I)_zac.preexec]-0} == 0 )); then
    _zac.debug.log "init | hook preexec"
    preexec_functions+=(_zac.preexec)
  fi

  # Signal handler: keep it cheap. Do not run tmux/osascript here.
  #
  # Exception: TRAPUSR1 must be global for this shell process.
  # `emulate -L/-LR` enables local trap scoping; disable it right before
  # defining traps.
  builtin unsetopt localtraps 2>/dev/null
  #
  # TRAPUSR1 is global per-shell state, so if another plugin already defined a
  # handler we chain it.
  if (( ! _zac[guard.trapusr1_wrapped] )); then
    if (( $+functions[TRAPUSR1] )); then
      # Preserve any existing handler before we overwrite it.
      # (Copying is cheaper and avoids re-parsing function text.)
      # If this ever breaks on an older zsh, consider copying via `functions[...]`.
      functions -c TRAPUSR1 _zac.trapusr1.prev 2>/dev/null
    fi

    TRAPUSR1() {
      _zac[state.needs_sync]=1
      (( $+functions[_zac.trapusr1.prev] )) && _zac.trapusr1.prev
    }

    _zac[guard.trapusr1_wrapped]=1
  fi

  # Intentional non-feature:
  # We do not attempt to redraw the prompt when appearance changes arrive while
  # the user is actively editing a command line in ZLE.
  # The plugin only flips state.needs_sync in TRAPUSR1, and the next prompt/Enter
  # will sync+propagate normally.

  _zac.debug.log "init | done"
}

# Propagate from _zac[state.is_dark] -> plugin vars.
function _zac.propagate() {
  # Apply cached state to prompt-related variables.
  #
  # This function must be fast and side-effect-safe because it can be called
  # from hooks. It does not query tmux/OS.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  (( _zac[state.defer_propagate] )) && return
  _zac[state.needs_propagate]=0

  _zac.debug.log "core | propagate | is_dark=${_zac[state.is_dark]:-}"

  local cb=${_zac[cfg.callback_fnc]}
  if [[ -n $cb && $+functions[$cb] -eq 1 ]]; then
    local is_dark=${_zac[state.is_dark]:-0}
     
    $cb $is_dark
  fi
}

function _zac.sync() {
  # Sync cached is_dark with the external ground truth.
  #
  # Ground truth is queried via _zac.dark_mode.query_ground_truth (platform).
  # If the value changes, we update the cache and set state.needs_propagate=1.
  # Callers decide whether/when to propagate.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  local is_dark old_mode changed=0

  _zac.debug.log "core | sync | start"
  _zac.dark_mode.query_ground_truth
  is_dark=$REPLY

  _zac.debug.log "core | sync | ground_truth=${is_dark}"

  old_mode=${_zac[state.is_dark]}
  if [[ $old_mode != $is_dark ]]; then
    _zac[state.is_dark]=$is_dark
    changed=1
    _zac[state.needs_propagate]=1
  fi

  _zac.debug.log "core | sync | changed=${changed}"

  _zac[state.needs_sync]=0
}

function _zac.precmd() {
  # precmd hook: runs right before the prompt is shown.
  # Used to perform deferred sync work and to perform one-time propagation
  # after the initial defer window.
  if (( _zac[state.defer_propagate] )); then
    _zac.debug.log "core | precmd | first prompt"
    _zac[state.defer_propagate]=0
    # First prompt is our "safe point": other prompt plugins/themes have
    # typically finished their startup work, so we can propagate without
    # immediately being overwritten.
    _zac[state.needs_propagate]=1
  fi

  if (( _zac[state.needs_sync] )); then
    _zac.debug.log "core | precmd | needs_sync=1"
    _zac.sync
  fi

  if (( _zac[state.needs_propagate] )); then
    _zac.propagate
  fi
}

function _zac.preexec() {
  # preexec hook: runs after Enter, right before executing the command.
  # This helps keep state correct even if a signal arrived while the user was
  # sitting at a prompt (no precmd ran yet).
  if (( _zac[state.needs_sync] )); then
    _zac.debug.log "core | preexec | needs_sync=1"
    _zac.sync
  fi

  if (( _zac[state.needs_propagate] )); then
    _zac.propagate
  fi
}

# Self-init when sourced.
_zac.init
