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
  local value tpl script

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
