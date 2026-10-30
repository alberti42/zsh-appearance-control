# Helpers available in every test. Sourced by tests/run inside each test's
# subshell, with $T set to the test's temporary directory (also the cwd) and
# ZAC_CACHE_DIR set to $T/cache.

export PLUGIN=$REPO_ROOT/zsh-appearance-control.plugin.zsh
export DISPATCH=$REPO_ROOT/bin/appearance-dispatch
export WATCH_LINUX=$REPO_ROOT/watchers/linux/zac-watch-linux

# --- outcome -----------------------------------------------------------------

function fail() {
  print -r -- "assertion failed: $*" >&2
  exit 1
}

function skip() {
  print -r -- "$*"
  exit 200
}

# --- assertions --------------------------------------------------------------

function assert_eq() {
  # assert_eq <actual> <expected> [what]
  [[ $1 == "$2" ]] && return 0
  fail "${3:-values differ}
  expected: ${(qqq)2}
  actual:   ${(qqq)1}"
}

function assert_contains() {
  # assert_contains <haystack> <needle> [what]
  [[ $1 == *"$2"* ]] && return 0
  fail "${3:-text does not contain ${(qqq)2}}
  text: ${(qqq)1}"
}

function assert_not_contains() {
  # assert_not_contains <haystack> <needle> [what]
  [[ $1 != *"$2"* ]] && return 0
  fail "${3:-text contains ${(qqq)2}}
  text: ${(qqq)1}"
}

function assert_file() {
  [[ -e $1 ]] || fail "file does not exist: $1"
}

function assert_no_file() {
  [[ ! -e $1 ]] || fail "file exists: $1"
}

function assert_content() {
  # assert_content <file> <expected>
  [[ -r $1 ]] || fail "file is not readable: $1"
  assert_eq "$(<$1)" "$2" "content of $1"
}

function assert_rc() {
  # assert_rc <expected>: checks the status of the last `run`.
  [[ $rc == $1 ]] && return 0
  fail "exit status: expected $1, got $rc
  output: ${(qqq)out}"
}

# --- running things ----------------------------------------------------------

function run() {
  # run <command...>: sets $out (stdout and stderr) and $rc.
  typeset -g out rc
  out=$("$@" 2>&1)
  rc=$?
}

function zsh_session() {
  # Feeds stdin to a fresh interactive zsh, which runs precmd and preexec as at
  # a real prompt. Sets $out (stdout), $err (stderr, prompts included) and $rc.
  typeset -g out err rc
  out=$(command zsh -f -i 2>$T/.session-stderr)
  rc=$?
  err=$(<$T/.session-stderr)
}

function spawn() {
  # spawn <command...>: starts it in the background; the runner kills it when
  # the test ends. Sets $REPLY to its pid.
  "$@" &
  typeset -g REPLY=$!
  print -r -- $REPLY >>$T/.spawned
}

function wait_for() {
  # wait_for <condition> [seconds]: polls the condition (evaluated) every 50 ms.
  local -i i limit=$(( ${2:-5} * 20 ))
  for (( i = 0; i < limit; i++ )); do
    eval "$1" && return 0
    command sleep 0.05
  done
  fail "timed out after ${2:-5} s waiting for: $1"
}

function set_appearance() {
  # set_appearance <0|1>: writes the cache file as the dispatcher would.
  command mkdir -p -- $ZAC_CACHE_DIR
  print -r -- $1 >| $ZAC_CACHE_DIR/appearance
}

function fake_dispatcher() {
  # fake_dispatcher <path>: an executable that records each call as a line
  # "<args> io=<ZAC_IO_CMD>" in <path>.calls, and exits with the status written
  # in <path>.rc (default 0). Each line of <path>.rc is used once, the last one
  # for all further calls.
  #
  # (Not named `path`: in zsh that is the array tied to PATH.)
  local file=$1
  print -r -- "#!/bin/sh
print_status() {
  [ -s '$file.rc' ] || { echo 0; return; }
  n=\$(wc -l < '$file.calls' | tr -d ' ')
  sed -n \"\${n}p\" '$file.rc' | grep . || tail -n 1 '$file.rc'
}
echo \"\$* io=\${ZAC_IO_CMD:-}\" >> '$file.calls'
exit \$(print_status)" > $file
  command chmod +x $file
  : >| $file.calls
}
