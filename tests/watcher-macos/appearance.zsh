# watchers/macos/zac-watch-macos when the appearance really changes. The other
# macOS watcher tests read the appearance but never change it.
#
# These tests change the appearance of the Mac they run on, so they run only
# when REAL_APPEARANCE_TESTS=1, and are meant for a CI runner. Each one puts the
# original appearance back when it ends. The macOS CI job sets the variable.
#
# Two ways to change it:
#   - `defaults write -g AppleInterfaceStyle Dark` changes the key the watcher
#     reads, with no permission needed; macOS does not post its notification
#     for that, so the test posts it (post-notification.swift).
#   - System Events through osascript, as `zac dark` does: macOS switches the
#     appearance and posts the notification itself. It needs the Automation
#     permission, so that test skips where it is not granted.

function real_appearance() {
  [[ $OSTYPE == darwin* ]] || skip "macOS only"
  [[ ${REAL_APPEARANCE_TESTS:-} == 1 ]] \
    || skip "changes the appearance of this Mac: set REAL_APPEARANCE_TESTS=1, on a CI runner"
  typeset -g WATCH_MACOS=${WATCH_MACOS_BIN:-$REPO_ROOT/watchers/macos/.build/release/zac-watch-macos}
  [[ -x $WATCH_MACOS ]] || fail "REAL_APPEARANCE_TESTS=1, but the watcher is not built: run 'make watcher-macos'"

  typeset -g ORIGINAL_STYLE
  ORIGINAL_STYLE=$(defaults read -g AppleInterfaceStyle 2>/dev/null) || ORIGINAL_STYLE=''

  fake_dispatcher $T/dispatch
  export ZAC_DISPATCH=$T/dispatch
}

function restore_appearance() {
  if [[ -n $ORIGINAL_STYLE ]]; then
    defaults write -g AppleInterfaceStyle "$ORIGINAL_STYLE"
  else
    defaults delete -g AppleInterfaceStyle 2>/dev/null
  fi
  post_notification
}

function style() {
  # style <dark|light>: sets the key the watcher reads.
  if [[ $1 == dark ]]; then
    defaults write -g AppleInterfaceStyle Dark
  else
    defaults delete -g AppleInterfaceStyle 2>/dev/null
  fi
}

function post_notification() {
  swift $TESTS_DIR/watcher-macos/post-notification.swift ${1:-1} || fail "could not post the notification"
}

function start_watcher() {
  spawn $WATCH_MACOS </dev/null >$T/log 2>&1
  wait_for '[[ $(<$T/log) == *"startup: dispatched"* ]]'
}

function count_checks() {
  local -a lines=( ${(M)${(f)"$(<$T/log)"}:#*notification:*} )
  REPLY=$#lines
}

function test_change_of_the_key_is_dispatched() {
  real_appearance
  trap restore_appearance EXIT
  style light
  start_watcher
  assert_contains "$(<$T/log)" "startup: dispatched 0 (light)"

  style dark
  post_notification
  wait_for '[[ $(<$T/log) == *"notification: dispatched 1 (dark)"* ]]'

  style light
  post_notification
  wait_for '[[ $(<$T/log) == *"notification: dispatched 0 (light)"* ]]'
  assert_content $T/dispatch.calls $'dispatch 0 io=\ndispatch 1 io=\ndispatch 0 io='
}

function test_burst_after_a_change_gives_one_dispatch() {
  real_appearance
  trap restore_appearance EXIT
  style light
  start_watcher
  style dark
  post_notification 5
  wait_for '[[ $(<$T/log) == *"notification: dispatched 1 (dark)"* ]]'
  sleep 0.5
  count_checks
  assert_eq $REPLY 1 "checks after a burst of 5 notifications"
  assert_content $T/dispatch.calls $'dispatch 0 io=\ndispatch 1 io='
}

function test_key_written_after_the_notification_is_seen() {
  # The notification can arrive a moment before the defaults are updated; the
  # watcher reads the value only when the debounce window (150 ms) has passed.
  real_appearance
  trap restore_appearance EXIT
  style light
  start_watcher
  post_notification
  sleep 0.05
  style dark
  wait_for '[[ $(<$T/log) == *"notification: dispatched 1 (dark)"* ]]'
}

function test_system_events_switch_is_dispatched() {
  real_appearance
  local start
  start=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2>&1)
  [[ $start == (true|false) ]] || skip "System Events is not available: $start"
  trap "osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to $start' >/dev/null 2>&1" EXIT

  local target=true want='1 (dark)'
  [[ $start == true ]] && { target=false; want='0 (light)' }

  start_watcher
  # A permission prompt would block for ever: give up after 20 s.
  run perl -e 'alarm 20; exec @ARGV' osascript -e \
    "tell application \"System Events\" to tell appearance preferences to set dark mode to $target"
  (( rc == 0 )) || skip "System Events refused to switch the appearance (rc=$rc): $out"
  wait_for '[[ $(<$T/log) == *"notification: dispatched $want"* ]]' 10
}
