# bin/appearance-dispatch: only shells that registered are signalled. USR1
# terminates a process that has no handler for it, so a wrong signal kills.

function register_pid() {
  # register_pid <pid> [seconds before now]
  zmodload zsh/datetime
  mkdir -p $ZAC_CACHE_DIR/pids
  print -r -- $(( EPOCHSECONDS - ${2:-0} )) > $ZAC_CACHE_DIR/pids/$1
}

function test_registered_shell_runs_its_callback() {
  set_appearance 0
  spawn zsh -f -i -c '
    cb() { print -r -- $1 >> got }
    export ZAC_IMMEDIATE_CALLBACK_FNC=cb
    source $PLUGIN
    : > ready
    repeat 100 { [[ -e got && $(<got) == *1 ]] && break; sleep 0.1 }
  ' </dev/null >/dev/null 2>&1
  wait_for '[[ -e ready ]]'
  run $DISPATCH dispatch 1
  assert_rc 0
  # Only the value USR1 delivers: this shell never shows a prompt, so it never
  # runs the hooks, and the startup call of the callback does not happen.
  local want=1
  wait_for '[[ $(<got) == $want ]]'
}

function test_unregistered_shell_is_not_signalled() {
  spawn zsh -f -c 'sleep 30; :'
  local pid=$REPLY
  run $DISPATCH dispatch 1
  assert_rc 0
  kill -0 $pid 2>/dev/null || fail "the shell died"
}

function test_registered_process_that_is_not_zsh_is_not_signalled() {
  spawn sleep 30
  local pid=$REPLY
  register_pid $pid
  run $DISPATCH dispatch 1
  assert_rc 0
  kill -0 $pid 2>/dev/null || fail "the process died"
}

function test_registration_older_than_the_process_is_a_reused_pid() {
  # A shell without the plugin: USR1 would kill it.
  spawn zsh -f -c 'sleep 30; :'
  local pid=$REPLY
  sleep 0.2
  register_pid $pid 100
  run $DISPATCH dispatch 1
  assert_rc 0
  kill -0 $pid 2>/dev/null || fail "the shell died"
  assert_no_file $ZAC_CACHE_DIR/pids/$pid
}

function test_registration_of_a_dead_process_is_removed() {
  command true &
  local pid=$!
  wait $pid
  register_pid $pid
  run $DISPATCH dispatch 1
  assert_rc 0
  assert_no_file $ZAC_CACHE_DIR/pids/$pid
}

function test_malformed_registrations_are_removed() {
  mkdir -p $ZAC_CACHE_DIR/pids
  print -r -- 123 > $ZAC_CACHE_DIR/pids/not-a-pid
  print -r -- garbage > $ZAC_CACHE_DIR/pids/$$
  run $DISPATCH dispatch 1
  assert_rc 0
  assert_no_file $ZAC_CACHE_DIR/pids/not-a-pid
  assert_no_file $ZAC_CACHE_DIR/pids/$$
}
