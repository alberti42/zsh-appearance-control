# Loading the plugin: the cache file is read and the callbacks run once.

function test_noninteractive_shell_defines_nothing() {
  run zsh -f -c 'source $PLUGIN; print -r -- ${+functions[zac]} ${+functions[TRAPUSR1]}'
  assert_rc 0
  assert_eq "$out" "0 0"
}

function test_load_reads_the_cache_file() {
  set_appearance 1
  zsh_session <<'EOF'
source $PLUGIN
zac status
EOF
  assert_eq "$out" 1
}

function test_missing_cache_file_is_unknown() {
  zsh_session <<'EOF'
source $PLUGIN
zac status; print -r -- "rc=$?"
EOF
  assert_eq "$out" $'0\nrc=1'
}

function test_immediate_callback_runs_once_before_first_prompt() {
  # Not during the load: called from _zac.init it would run under the
  # plugin's emulate options instead of the user's.
  set_appearance 1
  zsh_session <<'EOF'
cb() { print -r -- "cb $1" }
export ZAC_IMMEDIATE_CALLBACK_FNC=cb
source $PLUGIN; print -r -- loaded
print -r -- next
EOF
  assert_eq "$out" $'loaded\ncb 1\nnext'
}

function test_immediate_callback_defined_after_load_runs_before_first_prompt() {
  # As in a .zshrc that defines the function below the plugin line: both happen
  # before the first prompt.
  set_appearance 1
  zsh_session <<'EOF'
export ZAC_IMMEDIATE_CALLBACK_FNC=cb
source $PLUGIN; print -r -- loaded; cb() { print -r -- "cb $1" }
print -r -- next
EOF
  assert_eq "$out" $'loaded\ncb 1\nnext'
}

function test_immediate_callback_runs_with_user_options() {
  # The plugin's functions run under warn_create_global; a callback called from
  # inside them would warn on a plain global assignment.
  set_appearance 1
  zsh_session <<'EOF'
cb() { NEW_GLOBAL_FROM_CB=$1 }
export ZAC_IMMEDIATE_CALLBACK_FNC=cb
source $PLUGIN
print -r -- $NEW_GLOBAL_FROM_CB
EOF
  assert_eq "$out" 1
  assert_not_contains "$err" "created globally"
}

function test_deferred_callback_runs_at_first_prompt_not_at_load() {
  set_appearance 1
  zsh_session <<'EOF'
d() { print -r -- "deferred $1" }
export ZAC_DEFERRED_CALLBACK_FNC=d
source $PLUGIN; print -r -- loaded
print -r -- next
EOF
  assert_eq "$out" $'loaded\ndeferred 1\nnext'
}

function test_legacy_ZAC_CALLBACK_FNC_is_the_deferred_callback() {
  set_appearance 0
  zsh_session <<'EOF'
d() { print -r -- "deferred $1" }
export ZAC_CALLBACK_FNC=d
source $PLUGIN; print -r -- loaded
EOF
  assert_eq "$out" $'loaded\ndeferred 0'
}
