# Core runtime for zsh-appearance-control.
#
# This file implements:
# - the state machine for "needs_sync" and "logon" handling
# - the sync path that reads ground truth and updates cached is_dark
# - the propagation path that updates prompt-related variables / callback
#
# State keys used (see also zsh-appearance-control.plugin.zsh):
# - _zsh_appearance_control[is_dark]                cached boolean (0/1)
# - _zsh_appearance_control[needs_sync]             1 => call _zac.sync soon
# - _zsh_appearance_control[logon]                  1 => avoid touching others
# - _zsh_appearance_control[needs_init_propagate]   1 => propagate once post-logon
# - _zsh_appearance_control[last_sync_changed]      1 => last sync changed is_dark
# - _zsh_appearance_control[callback.fnc]           optional function name
# - _zsh_appearance_control[on_change.redraw_prompt] if sync runs in ZLE, redraw

function _zac.init() {
  # One-time initialization performed after modules are loaded.
  #
  # Note: we intentionally do not query external state here.
  (( ${+_zsh_appearance_control[_inited]} )) && return 0
  _zac.debug.log "core | init"
  _zsh_appearance_control[_inited]=1

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
