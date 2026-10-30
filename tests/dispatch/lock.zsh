# bin/appearance-dispatch: the lock that serializes dispatches.

function dead_pid() {
  # Sets REPLY to the pid of a process that has exited.
  command true &
  typeset -g REPLY=$!
  wait $REPLY
}

function test_lock_is_released_after_a_dispatch() {
  run $DISPATCH dispatch 1
  assert_rc 0
  assert_no_file $ZAC_CACHE_DIR/io.lock
}

function test_lock_of_a_dead_owner_is_stolen() {
  dead_pid
  mkdir -p $ZAC_CACHE_DIR/io.lock
  print -r -- $REPLY > $ZAC_CACHE_DIR/io.lock/pid
  run $DISPATCH dispatch 1
  assert_rc 0
  assert_contains "$out" "stealing lock of dead pid $REPLY"
  assert_content $ZAC_CACHE_DIR/appearance 1
}

function test_lock_of_a_live_owner_is_respected() {
  spawn sleep 30
  mkdir -p $ZAC_CACHE_DIR/io.lock
  print -r -- $REPLY > $ZAC_CACHE_DIR/io.lock/pid
  run $DISPATCH dispatch 1
  assert_rc 1
  assert_contains "$out" "failed to acquire lock"
  assert_no_file $ZAC_CACHE_DIR/appearance
}

function test_ownerless_lock_older_than_a_minute_is_stolen() {
  zmodload zsh/datetime
  local stamp
  strftime -s stamp %Y%m%d%H%M $(( EPOCHSECONDS - 120 ))
  mkdir -p $ZAC_CACHE_DIR/io.lock
  touch -t $stamp $ZAC_CACHE_DIR/io.lock
  run $DISPATCH dispatch 1
  assert_rc 0
  assert_contains "$out" "stealing stale lock"
}

function test_fresh_ownerless_lock_is_respected() {
  # Its owner may not have written its pid yet.
  mkdir -p $ZAC_CACHE_DIR/io.lock
  run $DISPATCH dispatch 1
  assert_rc 1
  assert_contains "$out" "failed to acquire lock"
}
