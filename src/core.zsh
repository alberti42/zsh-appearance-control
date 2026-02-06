# Core runtime for zsh-appearance-control.

function _zac.init() {
  (( ${+_zsh_appearance_control[_inited]} )) && return 0
  _zsh_appearance_control[_inited]=1

  local in_zle=0
  [[ -n ${ZLE_STATE-} ]] && in_zle=1

  _zsh_appearance_control[needs_sync]=1
  _zsh_appearance_control[needs_init_propagate]=0
  _zsh_appearance_control[last_sync_changed]=0

  if (( in_zle )); then
    _zsh_appearance_control[logon]=0
  else
    _zsh_appearance_control[logon]=1
  fi
}

# Propagate from _zsh_appearance_control[is_dark] -> plugin vars.
function _zac.propagate() {
  (( _zsh_appearance_control[logon] )) && return

  local cb=${_zsh_appearance_control[callback.fnc]}
  if [[ -n $cb && $+functions[$cb] -eq 1 ]]; then
    local is_dark=${_zsh_appearance_control[is_dark]:-0}
    
    $cb $is_dark
  fi
}

function _zac.sync() {
  local is_dark old_mode changed=0

  _zac.dark_mode.query_ground_truth
  is_dark=$REPLY

  old_mode=${_zsh_appearance_control[is_dark]}
  if [[ $old_mode != $is_dark ]]; then
    _zsh_appearance_control[is_dark]=$is_dark
    changed=1
    _zac.propagate
  fi

  _zsh_appearance_control[last_sync_changed]=$changed
  _zsh_appearance_control[needs_sync]=0

  if (( changed )) && (( _zsh_appearance_control[on_change.redraw_prompt] )) && [[ -n ${ZLE_STATE-} ]]; then
    zle reset-prompt 2>/dev/null
  fi
}

function _zac.precmd() {
  if (( _zsh_appearance_control[logon] )); then
    _zsh_appearance_control[logon]=0
    _zsh_appearance_control[needs_sync]=1
    _zsh_appearance_control[needs_init_propagate]=1
  fi

  if (( _zsh_appearance_control[needs_sync] )); then
    _zac.sync
  fi

  if (( _zsh_appearance_control[needs_init_propagate] )); then
    _zsh_appearance_control[needs_init_propagate]=0
    if (( ! _zsh_appearance_control[last_sync_changed] )); then
      _zac.propagate
    fi
  fi
}

function _zac.preexec() {
  if (( _zsh_appearance_control[needs_sync] )); then
    _zac.sync
  fi
}
