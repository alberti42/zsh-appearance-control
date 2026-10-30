# The pid registry: a shell that loads the plugin registers itself, so that the
# dispatcher may signal it, and unregisters when it exits.

function test_shell_registers_its_pid_with_the_registration_time() {
  zsh_session <<'EOF'
source $PLUGIN
zmodload zsh/datetime
print -r -- $(( EPOCHSECONDS - $(<$ZAC_CACHE_DIR/pids/$$) <= 2 ))
EOF
  assert_eq "$out" 1
}

function test_shell_unregisters_on_exit() {
  zsh_session <<'EOF'
source $PLUGIN
print -r -- $$
EOF
  assert_file $ZAC_CACHE_DIR/pids
  assert_no_file $ZAC_CACHE_DIR/pids/$out
}

function test_cache_directories_are_private() {
  zsh_session <<'EOF'
source $PLUGIN
EOF
  zmodload -F zsh/stat b:zstat
  local -a mode
  zstat -A mode -o +mode $ZAC_CACHE_DIR $ZAC_CACHE_DIR/pids
  assert_eq "${mode[1][-3,-1]} ${mode[2][-3,-1]}" "700 700"
}
