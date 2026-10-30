# watchers/macos/zac-watch-macos, as a black box: the dispatcher is a fake that
# records its calls, and the appearance is the real one of this Mac, read with
# `defaults`. The tests never change the appearance.
#
# They need a built binary: `make watcher-macos`, or set WATCH_MACOS_BIN.

function macos_watcher() {
  [[ $OSTYPE == darwin* ]] || skip "macOS only"
  typeset -g WATCH_MACOS=${WATCH_MACOS_BIN:-$REPO_ROOT/watchers/macos/.build/release/zac-watch-macos}
  [[ -x $WATCH_MACOS ]] || skip "not built: run 'make watcher-macos', or set WATCH_MACOS_BIN"

  # The value the watcher must report: AppleInterfaceStyle is "Dark" in dark
  # mode and absent in light mode.
  typeset -g EXPECTED=0
  [[ $(defaults read -g AppleInterfaceStyle 2>/dev/null) == Dark* ]] && EXPECTED=1

  fake_dispatcher $T/dispatch
  export ZAC_DISPATCH=$T/dispatch
  export ZAC_WATCH_RETRY_MS=100
}

function start_watcher() {
  spawn $WATCH_MACOS </dev/null >$T/log 2>&1
  typeset -g WATCHER_PID=$REPLY
  wait_for '[[ $(<$T/log) == *"startup:"* ]]'
}

function test_version() {
  macos_watcher
  run $WATCH_MACOS --version
  assert_rc 0
  assert_contains "$out" "zac-watch-macos 2."
}

function test_help() {
  macos_watcher
  run $WATCH_MACOS --help
  assert_rc 0
  assert_contains "$out" "usage: zac-watch-macos"
}

function test_unknown_argument() {
  macos_watcher
  run $WATCH_MACOS --frobnicate
  assert_rc 2
  assert_contains "$out" "unknown argument: --frobnicate"
}

function test_print_reports_the_system_appearance() {
  macos_watcher
  run $WATCH_MACOS --print
  assert_rc 0
  assert_eq "$out" $EXPECTED
}

function test_once_dispatches_and_returns_the_dispatcher_status() {
  macos_watcher
  print -r -- 3 > $T/dispatch.rc
  run $WATCH_MACOS --once
  assert_rc 3
  assert_content $T/dispatch.calls "dispatch $EXPECTED io="
}

function test_dispatcher_that_is_not_executable() {
  macos_watcher
  export ZAC_DISPATCH=$T/missing
  run $WATCH_MACOS --once
  assert_rc 2
  assert_contains "$out" "ZAC_DISPATCH is not an executable file"
}

function test_startup_dispatches_the_current_value() {
  macos_watcher
  start_watcher
  wait_for '[[ $(<$T/log) == *"startup: dispatched $EXPECTED"* ]]'
  assert_content $T/dispatch.calls "dispatch $EXPECTED io="
}

function test_environment_reaches_the_dispatcher() {
  macos_watcher
  export ZAC_IO_CMD=/path/to/io-script
  start_watcher
  wait_for '[[ -s $T/dispatch.calls ]]'
  assert_content $T/dispatch.calls "dispatch $EXPECTED io=/path/to/io-script"
}

function test_burst_of_notifications_gives_one_check() {
  macos_watcher
  start_watcher
  wait_for '[[ $(<$T/log) == *"startup: dispatched"* ]]'
  swift $TESTS_DIR/watcher-macos/post-notification.swift 5 || fail "could not post the notification"
  local want=${${EXPECTED/1/dark}/0/light}
  wait_for '[[ $(<$T/log) == *"notification: already $want, skipped"* ]]'
  sleep 0.5
  local -a skipped=( ${(M)${(f)"$(<$T/log)"}:#*notification: already*} )
  assert_eq $#skipped 1 "checks after a burst of 5 notifications"
  assert_content $T/dispatch.calls "dispatch $EXPECTED io="
}

function test_failed_dispatch_is_retried_once() {
  macos_watcher
  print -r -- $'1\n0' > $T/dispatch.rc
  start_watcher
  wait_for '[[ $(<$T/log) == *"startup (retry): dispatched"* ]]'
  assert_content $T/dispatch.calls $'dispatch '$EXPECTED$' io=\ndispatch '$EXPECTED' io='
}

function test_failed_retry_is_not_retried_again() {
  macos_watcher
  print -r -- 1 > $T/dispatch.rc
  start_watcher
  wait_for '[[ $(<$T/log) == *"startup (retry): dispatcher exited 1"* ]]'
  sleep 0.5
  assert_content $T/dispatch.calls $'dispatch '$EXPECTED$' io=\ndispatch '$EXPECTED' io='
}

function test_sigterm_stops_the_watcher() {
  macos_watcher
  start_watcher
  kill -TERM $WATCHER_PID
  wait $WATCHER_PID
  assert_eq $? 0 "exit status after SIGTERM"
  assert_contains "$(<$T/log)" "received signal 15, exiting"
}
