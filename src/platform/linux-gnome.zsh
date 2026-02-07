#!/usr/bin/env zsh

# Linux GNOME implementation.
#
# Uses gsettings to query/set GNOME's preferred color scheme.

function _zac.os_dark_mode.query() {
  # Query OS dark mode.
  # Sets REPLY to 1 (dark) or 0 (light).
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  command -v gsettings >/dev/null 2>&1 || return 1

  local v
  read -r v < <(command gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || v=''

  # gsettings returns quoted values like: 'prefer-dark' or 'default'
  v=${v//\'/}

  [[ $v == prefer-dark ]] && REPLY=1 || REPLY=0
}

function _zac.os_dark_mode.set() {
  # Request OS dark mode to be set.
  #
  # Arguments:
  # - $1: 1 to enable dark mode, 0 to disable.
  builtin emulate -LR zsh -o warn_create_global -o no_short_loops

  command -v gsettings >/dev/null 2>&1 || return 1

  local target=$1
  local scheme
  (( target )) && scheme=prefer-dark || scheme=default

  command gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null
}
