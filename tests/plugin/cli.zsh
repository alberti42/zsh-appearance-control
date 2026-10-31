# The zac command. The OS setter is replaced by a stub: changing the real
# appearance needs a desktop session and, on macOS, Automation permissions.

function test_zac_sync_rereads_the_cache_file() {
  set_appearance 1
  zsh_session <<'EOF'
source $PLUGIN
print -r -- 0 >| $ZAC_CACHE_DIR/appearance
zac status
zac sync
zac status
EOF
  assert_eq "$out" $'1\n0'
}

function test_zac_toggle_dark_light_ask_the_os_and_update_the_shell() {
  set_appearance 1
  zsh_session <<'EOF'
d() { print -r -- "deferred $1" }
export ZAC_DEFERRED_CALLBACK_FNC=d
source $PLUGIN
zac status >/dev/null
_zac.os_dark_mode.set() { print -r -- "os $1" }
zac toggle; zac status
zac dark; zac status
zac light; zac status
EOF
  # The deferred callback runs at the next prompt, after the command line.
  assert_eq "$out" $'deferred 1\nos 0\n0\ndeferred 0\nos 1\n1\ndeferred 1\nos 0\n0\ndeferred 0'
}

function test_zac_reports_an_unsupported_platform() {
  set_appearance 1
  zsh_session <<'EOF'
source $PLUGIN
zac status >/dev/null
_zac.os_dark_mode.set() { return 1 }
zac dark 2>&1; print -r -- "rc=$?"; zac status
EOF
  assert_contains "$out" "zac: unsupported platform"
  assert_contains "$out" $'rc=1\n1'
}

function test_zac_help() {
  zsh_session <<'EOF'
source $PLUGIN
zac --help
EOF
  assert_eq "$out" "usage: zac <status|sync|toggle|dark|light|debug>"
}

function test_zac_unknown_command() {
  zsh_session <<'EOF'
source $PLUGIN
zac frobnicate 2>&1; print -r -- "rc=$?"
EOF
  assert_eq "$out" $'zac: unknown command: frobnicate\nrc=2'
}
