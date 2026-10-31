# Callbacks run with the user's shell options, not with the plugin's emulate
# options, wherever the plugin calls them from. The test pattern `^x*` matches
# "abc" only when extended_glob is on; it is built at run time, so the option in
# effect when the callback runs decides.

function callbacks_that_report_extended_glob() {
  # Prints session lines that turn extended_glob on, as a user's .zshrc might,
  # and define two callbacks that report whether the option is in effect.
  print -r -- 'setopt extended_glob
_glob() { local p="^x*"; [[ abc == ${~p} ]] && print -r -- on || print -r -- off }
imm() { print -r -- "immediate $1 extended_glob=$(_glob)" }
def() { print -r -- "deferred $1 extended_glob=$(_glob)" }
export ZAC_IMMEDIATE_CALLBACK_FNC=imm ZAC_DEFERRED_CALLBACK_FNC=def'
}

function test_callbacks_see_user_options_at_startup() {
  set_appearance 1
  { callbacks_that_report_extended_glob
    print -r -- 'source $PLUGIN'
  } | zsh_session
  assert_contains "$out" "immediate 1 extended_glob=on"
  assert_contains "$out" "deferred 1 extended_glob=on"
}

function test_callbacks_see_user_options_after_usr1() {
  set_appearance 1
  { callbacks_that_report_extended_glob
    print -r -- 'source $PLUGIN'
    print -r -- 'print -r -- 0 >| $ZAC_CACHE_DIR/appearance; kill -USR1 $$'
    print -r -- 'print -r -- next'
  } | zsh_session
  assert_contains "$out" "immediate 0 extended_glob=on"
  assert_contains "$out" "deferred 0 extended_glob=on"
}

function test_deferred_callback_sees_user_options_after_zac_toggle() {
  set_appearance 1
  { callbacks_that_report_extended_glob
    print -r -- 'source $PLUGIN'
    print -r -- 'zac status >/dev/null; _zac.os_dark_mode.set() { : }'
    print -r -- 'zac toggle'
  } | zsh_session
  assert_contains "$out" "deferred 0 extended_glob=on"
}

function test_deferred_callback_assigning_a_global_does_not_warn() {
  # The plugin's own functions run under warn_create_global; a callback called
  # from inside them would warn on a plain global assignment.
  set_appearance 1
  zsh_session <<'EOF'
def() { NEW_GLOBAL_FROM_DEFERRED=$1 }
export ZAC_DEFERRED_CALLBACK_FNC=def
source $PLUGIN
print -r -- $NEW_GLOBAL_FROM_DEFERRED
EOF
  assert_eq "$out" 1
  assert_not_contains "$err" "created globally"
}
