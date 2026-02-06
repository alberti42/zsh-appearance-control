#!/usr/bin/env zsh

# macOS implementation.
#
# Uses AppleScript via `osascript` to query/set System Events -> appearance
# preferences -> dark mode.
#
# Notes:
# - _zac.os_dark_mode.set runs asynchronously (background) to avoid blocking.
# - REPLY is used as a conventional "return value" channel.

function _zac.os_dark_mode.query() {
  # Query OS dark mode.
  # Sets REPLY to 1 (dark) or 0 (light).
  local v

  _zac.debug.log "darwin | query os_dark_mode"

  v=$(command osascript 2>/dev/null <<'OSA'
tell application "System Events"
	tell appearance preferences
		get dark mode
	end tell
end tell
OSA
  )

  [[ $v == true ]] && REPLY=1 || REPLY=0

  _zac.debug.log "darwin | os_dark_mode=${REPLY}"
}

function _zac.os_dark_mode.set() {
  # Request OS dark mode to be set.
  #
  # Arguments:
  # - $1: 1 to enable dark mode, 0 to disable.
  #
  # Behavior:
  # - Sets REPLY to the requested target (0/1).
  # - Starts the osascript process in the background (&!) to avoid blocking.
  # - Does not guarantee that the OS has finished switching when it returns.
  local target=$1
  local value tpl script

  _zac.debug.log "darwin | set os_dark_mode target=${target}"

  REPLY=$target

  (( target )) && value=true || value=false

  tpl=$(command cat <<'OSA'
tell application "System Events"
	tell appearance preferences
		set dark mode to %s
	end tell
end tell
OSA
  )

  builtin printf -v script -- "$tpl" "$value"

  # Run in background to avoid blocking prompt during appearance switch.
  command osascript >/dev/null 2>&1 <<<"$script" &!
}
