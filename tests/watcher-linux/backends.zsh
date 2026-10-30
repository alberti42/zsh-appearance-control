# watchers/linux/zac-watch-linux with its desktop backends, the portal and
# gsettings. The real gdbus and gsettings are replaced by the fakes in fakes/,
# put first in PATH; each test writes the desktop state they report. No
# desktop or D-Bus is needed, so these tests also run on macOS.

function fake_desktop() {
  export FAKE_DESKTOP=$T/desktop
  mkdir -p $FAKE_DESKTOP
  : > $FAKE_DESKTOP/calls
  : > $FAKE_DESKTOP/portal-events
  : > $FAKE_DESKTOP/gsettings-events
  export PATH=$TESTS_DIR/watcher-linux/fakes:$PATH

  # The desktop backends refuse to start without a session bus. Nothing
  # connects to this address: only the fakes are called.
  export DBUS_SESSION_BUS_ADDRESS=unix:path=$T/no-bus

  export ZAC_WATCH_DETECT_TRIES=1
  export ZAC_WATCH_DETECT_WAIT_S=1
  export ZAC_WATCH_DEBOUNCE_MS=200
  fake_dispatcher $T/dispatch
  export ZAC_DISPATCH=$T/dispatch
}

function portal() { print -r -- $1 > $FAKE_DESKTOP/portal-value }
function gnome() { print -r -- $1 > $FAKE_DESKTOP/gsettings-value }

function start_watcher() {
  spawn zsh -f $WATCH_LINUX </dev/null >$T/log 2>&1
  wait_for '[[ $(<$T/log) == *"startup:"* ]]'
}

# --- reading the value -------------------------------------------------------

function test_portal_prefer_dark_is_dark() {
  fake_desktop
  portal 1
  run zsh -f $WATCH_LINUX --print
  assert_rc 0
  assert_eq "$out" 1
  assert_contains "$(<$FAKE_DESKTOP/calls)" \
    "--dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadOne org.freedesktop.appearance color-scheme"
}

function test_portal_no_preference_and_prefer_light_are_light() {
  fake_desktop
  local v
  for v in 0 2; do
    portal $v
    run zsh -f $WATCH_LINUX --print
    assert_rc 0
    assert_eq "$out" 0 "portal value $v"
  done
}

function test_portal_without_ReadOne_is_read_with_Read() {
  fake_desktop
  portal 1
  : > $FAKE_DESKTOP/portal-no-readone
  run zsh -f $WATCH_LINUX --print
  assert_rc 0
  assert_eq "$out" 1
  assert_contains "$(<$FAKE_DESKTOP/calls)" "--method org.freedesktop.portal.Settings.Read org.freedesktop.appearance"
}

function test_gsettings_values_map_like_the_plugin() {
  # The same mapping as src/platform/linux-gnome.zsh.
  fake_desktop
  export ZAC_WATCH_BACKEND=gsettings
  local v want
  for v want in prefer-dark 1 prefer-light 0 default 0; do
    gnome $v
    run zsh -f $WATCH_LINUX --print
    assert_rc 0
    assert_eq "$out" $want "gsettings value $v"
  done
  assert_contains "$(<$FAKE_DESKTOP/calls)" "gsettings get org.gnome.desktop.interface color-scheme"
}

# --- choosing the backend ----------------------------------------------------

function test_auto_prefers_the_portal() {
  fake_desktop
  portal 1
  gnome default
  run zsh -f $WATCH_LINUX --print
  assert_rc 0
  assert_eq "$out" 1
  assert_not_contains "$(<$FAKE_DESKTOP/calls)" "gsettings"
}

function test_auto_falls_back_to_gsettings_when_the_portal_is_silent() {
  fake_desktop
  gnome prefer-dark
  run zsh -f $WATCH_LINUX --print
  assert_rc 0
  assert_contains "$out" "the appearance portal did not answer; trying gsettings"
  assert_eq "${out##*$'\n'}" 1
}

function test_forced_portal_does_not_fall_back() {
  fake_desktop
  gnome prefer-dark
  export ZAC_WATCH_BACKEND=portal
  run zsh -f $WATCH_LINUX --print
  assert_rc 3
  assert_contains "$out" "no usable backend (asked for: portal)"
  assert_not_contains "$(<$FAKE_DESKTOP/calls)" "gsettings"
}

function test_no_backend_is_retried_then_given_up() {
  fake_desktop
  export ZAC_WATCH_DETECT_TRIES=2
  run zsh -f $WATCH_LINUX --print
  assert_rc 3
  assert_contains "$out" "no backend yet (attempt 1/2); waiting 1s"
  assert_contains "$out" "no usable backend"
}

function test_backend_that_comes_up_during_the_retries_is_used() {
  # As a second after login, when the portal is not up yet.
  fake_desktop
  export ZAC_WATCH_DETECT_TRIES=3
  ( sleep 0.5; print -r -- 1 > $FAKE_DESKTOP/portal-value ) &
  run zsh -f $WATCH_LINUX --print
  assert_rc 0
  assert_contains "$out" "no backend yet (attempt 1/3)"
  assert_eq "${out##*$'\n'}" 1
}

# --- watching ----------------------------------------------------------------

function test_portal_monitor_watches_the_portal_object() {
  fake_desktop
  portal 1
  start_watcher
  wait_for '[[ $(<$FAKE_DESKTOP/calls) == *"gdbus monitor"* ]]'
  assert_contains "$(<$FAKE_DESKTOP/calls)" \
    "gdbus monitor --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop"
}

function test_portal_reacts_only_to_color_scheme_changes() {
  fake_desktop
  portal 1
  start_watcher
  portal 2
  # What `gdbus monitor` prints when it starts, and a change of another setting.
  print -r -- "Monitoring signals on object /org/freedesktop/portal/desktop owned by :1.23
The name org.freedesktop.portal.Desktop is owned by :1.23
/org/freedesktop/portal/desktop: org.freedesktop.portal.Settings.SettingChanged ('org.freedesktop.appearance', 'accent-color', <(0.2, 0.4, 0.8)>)" \
    >> $FAKE_DESKTOP/portal-events
  sleep 0.6
  assert_not_contains "$(<$T/log)" "change:"

  print -r -- "/org/freedesktop/portal/desktop: org.freedesktop.portal.Settings.SettingChanged ('org.freedesktop.appearance', 'color-scheme', <uint32 2>)" \
    >> $FAKE_DESKTOP/portal-events
  wait_for '[[ $(<$T/log) == *"change: dispatched 0 (light)"* ]]'
  assert_content $T/dispatch.calls $'dispatch 1 io=\ndispatch 0 io='
}

function test_gsettings_monitor_reacts_to_every_line() {
  # `gsettings monitor <schema> <key>` watches one key, so its lines are not
  # filtered: their format differs between glib versions.
  fake_desktop
  export ZAC_WATCH_BACKEND=gsettings
  gnome default
  start_watcher
  assert_contains "$(<$FAKE_DESKTOP/calls)" "gsettings monitor org.gnome.desktop.interface color-scheme"
  gnome prefer-dark
  print -r -- "color-scheme: 'prefer-dark'" >> $FAKE_DESKTOP/gsettings-events
  wait_for '[[ $(<$T/log) == *"change: dispatched 1 (dark)"* ]]'
  assert_content $T/dispatch.calls $'dispatch 0 io=\ndispatch 1 io='
}

# --- the session bus ---------------------------------------------------------

function test_desktop_on_another_bus_is_reported() {
  # The watcher compares its bus with the one in the environment of the
  # desktop process, read from /proc. A copy of `sleep` named gnome-shell
  # stands in for the desktop.
  [[ -d /proc/self ]] || skip "needs /proc (Linux)"
  fake_desktop
  portal 1
  mkdir -p $T/desktop-bin
  cp $(command -v sleep) $T/desktop-bin/gnome-shell
  DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/the-desktop-bus spawn $T/desktop-bin/gnome-shell 30
  wait_for 'pgrep -x gnome-shell >/dev/null'
  start_watcher
  wait_for '[[ $(<$T/log) == *"WARNING: the desktop session is on a different D-Bus"* ]]'
  assert_contains "$(<$T/log)" "desktop: unix:path=/tmp/the-desktop-bus"
}
