# USR1: the shell re-reads the cache file and runs the callbacks.

function test_usr1_runs_the_immediate_callback_with_the_new_value() {
  set_appearance 1
  zsh_session <<'EOF'
cb() { print -r -- "cb $1" }
export ZAC_IMMEDIATE_CALLBACK_FNC=cb
source $PLUGIN
print -r -- 0 >| $ZAC_CACHE_DIR/appearance; kill -USR1 $$
zac status
EOF
  assert_eq "$out" $'cb 1\ncb 0\n0'
}

function test_usr1_runs_the_deferred_callback_at_the_next_prompt() {
  set_appearance 1
  zsh_session <<'EOF'
d() { print -r -- "deferred $1" }
export ZAC_DEFERRED_CALLBACK_FNC=d
source $PLUGIN
print -r -- 0 >| $ZAC_CACHE_DIR/appearance; kill -USR1 $$; print -r -- signalled
print -r -- next
EOF
  assert_eq "$out" $'deferred 1\nsignalled\ndeferred 0\nnext'
}

function test_usr1_with_unchanged_value_does_not_rerun_the_deferred_callback() {
  set_appearance 1
  zsh_session <<'EOF'
d() { print -r -- "deferred $1" }
export ZAC_DEFERRED_CALLBACK_FNC=d
source $PLUGIN
kill -USR1 $$; print -r -- signalled
print -r -- next
EOF
  assert_eq "$out" $'deferred 1\nsignalled\nnext'
}

function test_existing_TRAPUSR1_is_chained() {
  set_appearance 1
  zsh_session <<'EOF'
TRAPUSR1() { print -r -- previous }
source $PLUGIN
print -r -- 0 >| $ZAC_CACHE_DIR/appearance; kill -USR1 $$
zac status
EOF
  assert_eq "$out" $'previous\n0'
}
