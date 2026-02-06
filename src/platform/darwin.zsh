function _zac.os_dark_mode.query() {
  local v

  v=$(command osascript 2>/dev/null <<'OSA'
tell application "System Events"
	tell appearance preferences
		get dark mode
	end tell
end tell
OSA
  )

  [[ $v == true ]] && REPLY=1 || REPLY=0
}

function _zac.os_dark_mode.set() {
  local target=$1

  if (( target )); then
    command osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events"
	tell appearance preferences
		set dark mode to true
	end tell
end tell
OSA
  else
    command osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events"
	tell appearance preferences
		set dark mode to false
	end tell
end tell
OSA
  fi
}
