#!/usr/bin/env zsh

# Fallback platform implementation.
#
# These functions intentionally do not implement OS dark mode changes.
# They exist so that the rest of the plugin can be loaded without errors.

function _zac.os_dark_mode.query() {
  # Unsupported platform. Sets a default and returns failure.
  REPLY=0
  return 1
}

function _zac.os_dark_mode.set() {
  # Unsupported platform. Clears REPLY and returns failure.
  REPLY=''
  return 1
}
