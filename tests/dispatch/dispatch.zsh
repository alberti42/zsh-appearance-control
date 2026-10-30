# bin/appearance-dispatch: arguments, the cache file and ZAC_IO_CMD.

function io_script() {
  # io_script [status]: an io script that records each call in $T/io.calls.
  print -r -- "#!/bin/sh
echo \"\$*\" >> '$T/io.calls'
exit ${1:-0}" > $T/io
  chmod +x $T/io
  export ZAC_IO_CMD=$T/io
}

function test_no_arguments_prints_usage() {
  run $DISPATCH
  assert_rc 1
  assert_contains "$out" "usage: appearance-dispatch"
}

function test_invalid_mode_is_rejected() {
  run $DISPATCH dispatch maybe
  assert_rc 1
  assert_contains "$out" "invalid mode: maybe"
  assert_no_file $ZAC_CACHE_DIR/appearance
}

function test_unsupported_type_is_rejected() {
  run $DISPATCH frobnicate 1
  assert_rc 1
  assert_contains "$out" "unsupported type: frobnicate"
}

function test_every_spelling_of_the_mode_is_accepted() {
  local m
  for m in 1 on true enable enabled; do
    run $DISPATCH dispatch $m
    assert_rc 0
    assert_content $ZAC_CACHE_DIR/appearance 1
  done
  for m in 0 off false disable disabled; do
    run $DISPATCH dispatch $m
    assert_rc 0
    assert_content $ZAC_CACHE_DIR/appearance 0
  done
}

function test_legacy_tmux_and_cache_subcommands_dispatch() {
  run $DISPATCH tmux 1
  assert_rc 0
  assert_content $ZAC_CACHE_DIR/appearance 1
  run $DISPATCH cache 0
  assert_rc 0
  assert_content $ZAC_CACHE_DIR/appearance 0
}

function test_cache_file_and_directories_are_private() {
  run $DISPATCH dispatch 1
  zmodload -F zsh/stat b:zstat
  local -a mode
  zstat -A mode -o +mode $ZAC_CACHE_DIR $ZAC_CACHE_DIR/pids $ZAC_CACHE_DIR/appearance
  assert_eq "${mode[1][-3,-1]} ${mode[2][-3,-1]} ${mode[3][-3,-1]}" "700 700 600"
}

function test_default_cache_dir_follows_XDG_CACHE_HOME() {
  unset ZAC_CACHE_DIR
  run $DISPATCH dispatch 1
  assert_rc 0
  assert_content $XDG_CACHE_HOME/zac/appearance 1
}

function test_io_cmd_runs_once_per_change() {
  io_script
  run $DISPATCH dispatch 1
  assert_rc 0
  run $DISPATCH dispatch 1
  assert_rc 0
  run $DISPATCH dispatch 0
  assert_rc 0
  assert_content $T/io.calls $'1\n0'
  assert_content $ZAC_CACHE_DIR/io.last_applied 0
}

function test_failing_io_cmd_aborts_the_dispatch() {
  set_appearance 0
  io_script 1
  run $DISPATCH dispatch 1
  assert_rc 1
  assert_contains "$out" "ZAC_IO_CMD failed; aborting"
  assert_content $ZAC_CACHE_DIR/appearance 0
  assert_no_file $ZAC_CACHE_DIR/io.last_applied
  assert_no_file $ZAC_CACHE_DIR/io.lock
}

function test_io_cmd_reruns_after_a_failure() {
  io_script 1
  run $DISPATCH dispatch 1
  assert_rc 1
  io_script 0
  run $DISPATCH dispatch 1
  assert_rc 0
  assert_content $T/io.calls $'1\n1'
  assert_content $ZAC_CACHE_DIR/appearance 1
}

function test_cache_file_is_overwritten_in_place_by_default() {
  zmodload -F zsh/stat b:zstat
  local -a before after
  run $DISPATCH dispatch 1
  zstat -A before +inode $ZAC_CACHE_DIR/appearance
  run $DISPATCH dispatch 0
  zstat -A after +inode $ZAC_CACHE_DIR/appearance
  assert_eq "$after" "$before" "inode of the cache file"
}

function test_atomic_mode_replaces_the_cache_file() {
  zmodload -F zsh/stat b:zstat
  local -a before after
  export ZAC_CACHE_ATOMIC=1
  run $DISPATCH dispatch 1
  zstat -A before +inode $ZAC_CACHE_DIR/appearance
  run $DISPATCH dispatch 0
  zstat -A after +inode $ZAC_CACHE_DIR/appearance
  assert_content $ZAC_CACHE_DIR/appearance 0
  [[ $after != $before ]] || fail "atomic write kept the inode $before"
  assert_eq "$(print -r -- $ZAC_CACHE_DIR/appearance.*(N))" "" "temporary files left behind"
}
