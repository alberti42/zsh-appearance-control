# watchers/linux/zac-watch-linux, driven by its custom backend: the monitor is
# `tail -n +1 -f` on a file, one appended line per desktop signal, and the value is
# read from $T/state. The dispatcher is a fake that records its calls. No
# desktop or D-Bus is needed, so these tests also run on macOS.

function custom_backend() {
  fake_dispatcher $T/dispatch
  print -r -- 1 > $T/state
  : > $T/events
  export ZAC_DISPATCH=$T/dispatch
  export ZAC_WATCH_BACKEND=custom
  export ZAC_WATCH_MONITOR_CMD="tail -n +1 -f $T/events"
  export ZAC_WATCH_READ_CMD="cat $T/state"
  export ZAC_WATCH_DEBOUNCE_MS=200
  export ZAC_WATCH_RETRY_MS=100
}

function start_watcher() {
  spawn zsh -f $WATCH_LINUX </dev/null >$T/log 2>&1
  typeset -g WATCHER_PID=$REPLY
  wait_for '[[ $(<$T/log) == *"startup:"* ]]'
}

function signal_desktop() {
  # signal_desktop [count]: appends lines to the monitored file.
  repeat ${1:-1}; do
    print -r -- "color-scheme changed" >> $T/events
  done
}

function test_version() {
  run zsh -f $WATCH_LINUX --version
  assert_rc 0
  assert_contains "$out" "zac-watch-linux 2."
}

function test_help() {
  run zsh -f $WATCH_LINUX --help
  assert_rc 0
  assert_contains "$out" "usage: zac-watch-linux"
}

function test_unknown_argument() {
  run zsh -f $WATCH_LINUX --frobnicate
  assert_rc 2
  assert_contains "$out" "unknown argument: --frobnicate"
}

function test_print_reads_the_backend() {
  custom_backend
  print -r -- 0 > $T/state
  run zsh -f $WATCH_LINUX --print
  assert_rc 0
  assert_eq "$out" 0
}

function test_once_dispatches_and_returns_the_dispatcher_status() {
  custom_backend
  print -r -- 3 > $T/dispatch.rc
  run zsh -f $WATCH_LINUX --once
  assert_rc 3
  assert_content $T/dispatch.calls "dispatch 1 io="
}

function test_dispatcher_that_is_not_executable() {
  custom_backend
  export ZAC_DISPATCH=$T/missing
  run zsh -f $WATCH_LINUX --once
  assert_rc 2
  assert_contains "$out" "ZAC_DISPATCH is not an executable file"
}

function test_custom_backend_needs_both_commands() {
  custom_backend
  unset ZAC_WATCH_READ_CMD
  run zsh -f $WATCH_LINUX --print
  assert_rc 2
  assert_contains "$out" "needs both ZAC_WATCH_MONITOR_CMD and ZAC_WATCH_READ_CMD"
}

function test_desktop_backends_need_a_session_bus() {
  unset DBUS_SESSION_BUS_ADDRESS
  export XDG_RUNTIME_DIR=$T/no-runtime-dir
  export ZAC_WATCH_BACKEND=gsettings
  run zsh -f $WATCH_LINUX --print
  assert_rc 3
  assert_contains "$out" "no session D-Bus"
}

function test_startup_dispatches_the_current_value() {
  custom_backend
  start_watcher
  wait_for '[[ $(<$T/log) == *"startup: dispatched 1 (dark)"* ]]'
  assert_content $T/dispatch.calls "dispatch 1 io="
}

function test_environment_reaches_the_dispatcher() {
  custom_backend
  export ZAC_IO_CMD=/path/to/io-script
  start_watcher
  wait_for '[[ -s $T/dispatch.calls ]]'
  assert_content $T/dispatch.calls "dispatch 1 io=/path/to/io-script"
}

function test_burst_of_signals_gives_one_dispatch() {
  custom_backend
  start_watcher
  print -r -- 0 > $T/state
  signal_desktop 5
  wait_for '[[ $(<$T/log) == *"change: dispatched 0 (light)"* ]]'
  sleep 0.5
  local -a checks=( ${(M)${(f)"$(<$T/log)"}:#*change:*} )
  assert_eq $#checks 1 "checks after a burst of 5 signals"
  assert_content $T/dispatch.calls $'dispatch 1 io=\ndispatch 0 io='
}

function test_signal_without_a_change_is_skipped() {
  custom_backend
  start_watcher
  signal_desktop
  wait_for '[[ $(<$T/log) == *"change: already dark, skipped"* ]]'
  assert_content $T/dispatch.calls "dispatch 1 io="
}

function test_failed_dispatch_is_retried_once() {
  custom_backend
  print -r -- $'1\n0' > $T/dispatch.rc
  start_watcher
  wait_for '[[ $(<$T/log) == *"startup (retry): dispatched 1"* ]]'
  assert_content $T/dispatch.calls $'dispatch 1 io=\ndispatch 1 io='
}

function test_failed_retry_is_not_retried_again() {
  custom_backend
  print -r -- 1 > $T/dispatch.rc
  start_watcher
  wait_for '[[ $(<$T/log) == *"dispatcher failed again"* ]]'
  sleep 0.5
  assert_content $T/dispatch.calls $'dispatch 1 io=\ndispatch 1 io='
}

function test_watcher_exits_when_the_monitor_exits() {
  custom_backend
  export ZAC_WATCH_MONITOR_CMD=true
  run zsh -f $WATCH_LINUX
  assert_rc 1
  assert_contains "$out" "the monitor exited"
}

function test_sigterm_stops_the_watcher_and_its_monitor() {
  custom_backend
  start_watcher
  kill -TERM $WATCHER_PID
  wait $WATCHER_PID
  assert_eq $? 0 "exit status after SIGTERM"
  sleep 0.2
  local monitors=$(command ps -ax -o command= | command grep -F "tail -n +1 -f $T/events" | command grep -v grep)
  assert_eq "$monitors" "" "monitor processes left running"
}
