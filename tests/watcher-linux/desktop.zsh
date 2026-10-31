# watchers/linux/zac-watch-linux against a real session D-Bus, real dconf,
# real gsettings and a real xdg-desktop-portal. The other watcher tests replace
# the desktop with fakes; these check that the fakes match the real thing.
#
# They change org.gnome.desktop.interface color-scheme, so they run only when
# REAL_DESKTOP_TESTS=1, and are meant for a throwaway session. The Linux CI job
# runs them as:
#
#   XDG_CURRENT_DESKTOP=GNOME xvfb-run -a dbus-run-session -- \
#     env REAL_DESKTOP_TESTS=1 make test TESTS=tests/watcher-linux/desktop.zsh
#
# The portal backend needs xdg-desktop-portal and xdg-desktop-portal-gtk, which
# needs an X display: that is what xvfb-run is for.

function real_desktop() {
  [[ ${REAL_DESKTOP_TESTS:-} == 1 ]] \
    || skip "changes the desktop colour scheme: set REAL_DESKTOP_TESTS=1, in a throwaway session"
  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || fail "REAL_DESKTOP_TESTS=1, but there is no session D-Bus"

  # Put the user's value back when the test ends. In zsh an EXIT trap set in a
  # function runs when the function returns.
  typeset -g ORIGINAL_SCHEME
  ORIGINAL_SCHEME=$(gsettings get org.gnome.desktop.interface color-scheme) \
    || fail "gsettings cannot read org.gnome.desktop.interface color-scheme"
  scheme default

  export ZAC_DISPATCH=$DISPATCH
  export ZAC_WATCH_DEBOUNCE_MS=200
  print -r -- '#!/bin/sh
echo "$1" >> "$ZAC_CACHE_DIR/../io.calls"' > $T/io
  chmod +x $T/io
  export ZAC_IO_CMD=$T/io
}

function scheme() {
  gsettings set org.gnome.desktop.interface color-scheme $1
}

function start_watcher() {
  spawn zsh -f $WATCH_LINUX </dev/null >$T/log 2>&1
  wait_for '[[ $(<$T/log) == *"startup: dispatched"* ]]' 20
  # The monitor starts after the startup dispatch is logged.
  sleep 1
}

function count_changes() {
  local -a lines=( ${(M)${(f)"$(<$T/log)"}:#*change:*} )
  REPLY=$#lines
}

function test_gsettings_change_reaches_a_shell() {
  real_desktop
  trap 'scheme ${(Q)ORIGINAL_SCHEME}' EXIT
  export ZAC_WATCH_BACKEND=gsettings
  start_watcher
  assert_contains "$(<$T/log)" "startup: dispatched 0 (light)"

  # A shell that loads the plugin: its callback logs every value it receives.
  spawn zsh -f -i -c '
    cb() { print -r -- $1 >> got }
    export ZAC_IMMEDIATE_CALLBACK_FNC=cb
    source $PLUGIN
    : > ready
    repeat 200 { [[ -e got && $(<got) == *1 ]] && break; sleep 0.1 }
  ' </dev/null >/dev/null 2>&1
  wait_for '[[ -e ready ]]'

  scheme prefer-dark
  wait_for '[[ $(<$T/log) == *"change: dispatched 1 (dark)"* ]]' 10
  # Only the value USR1 delivers: this shell never shows a prompt, so it never
  # runs the hooks, and the startup call of the callback does not happen.
  local want=1
  wait_for '[[ $(<got) == $want ]]'
  assert_content $ZAC_CACHE_DIR/appearance 1
  assert_content $T/io.calls $'0\n1'
}

function test_portal_change_gives_one_dispatch() {
  # The portal emits two SettingChanged signals per change, one for
  # org.gnome.desktop.interface and one for org.freedesktop.appearance; the
  # debounce turns them into one dispatch.
  real_desktop
  trap 'scheme ${(Q)ORIGINAL_SCHEME}' EXIT
  export ZAC_WATCH_BACKEND=portal
  start_watcher
  assert_contains "$(<$T/log)" "watching (backend: portal"

  scheme prefer-dark
  wait_for '[[ $(<$T/log) == *"change: dispatched 1 (dark)"* ]]' 10
  sleep 1
  count_changes
  assert_eq $REPLY 1 "checks after one change"

  scheme prefer-light
  wait_for '[[ $(<$T/log) == *"change: dispatched 0 (light)"* ]]' 10
  assert_content $ZAC_CACHE_DIR/appearance 0
}

function test_auto_detection_picks_the_portal() {
  real_desktop
  trap 'scheme ${(Q)ORIGINAL_SCHEME}' EXIT
  start_watcher
  assert_contains "$(<$T/log)" "watching (backend: portal"
}
