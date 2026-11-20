#!/usr/bin/env bash
#
# test/20-restart.sh -- the restart question at the end of open.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/20-restart.sh".

source "$(dirname "$0")/lib.sh"

section "The restart question at the end of open"
# Only the question, with made-up answers: "yes" must call systemctl (the
# fake one; it prints that it was called), anything else must not. The
# number given to ask_restart is what "open" ends with (1: some changes
# could not be made); no answer may change it. After "yes" it counts
# down first; 2 seconds instead of 10 keep the tests short.
# The program's own code, loaded while the output goes nowhere: it then
# picks plain words for its badges (as in a file), not colours, even
# when this file runs in a terminal; the checks look for those words.
CC_ROOT="$ROOT"
source "$ROOT/lib/common.sh" >/dev/null
source "$ROOT/lib/items.sh"
source "$ROOT/lib/open.sh"
check "the countdown before a restart is 10 seconds" [ "$RESTART_WAIT" -eq 10 ]
RESTART_WAIT=2
for a in no YES ""; do
    s=0; out="$(printf '%s\n' "$a" | ask_restart 0 2>&1)" || s=$?
    check "answer \"$a\": no restart"                hasnt "$out" "systemctl reboot (ignored"
    check "... says so, with the command to restart"  sh -c 'printf "%s" "$1" | grep -qF "   WARN  Not restarted." && printf "%s" "$1" | grep -qF "       \$ systemctl reboot"' sh "$out"
    check "... exit 0"                               [ "$s" -eq 0 ]
done
s=0; out="$(printf 'no\n' | ask_restart 1 2>&1)" || s=$?
check "answer \"no\" after a failed change: exit 1"  [ "$s" -eq 1 ]
s=0; out="$(ask_restart 0 </dev/null 2>&1)" || s=$?
check "no answer at all (end of input): no restart"  hasnt "$out" "systemctl reboot (ignored"
check "... exit 0"                                   [ "$s" -eq 0 ]
check "the question says why to restart"             has "$out" "   INFO  The desktop shows some changes only after a restart."
check "... and that open programs close unsaved"     has "$out" "         Restarting closes every open program without asking to save."
# Ctrl+C while it waits for the answer ("timeout" sends it, as in
# 11-ctrl-c.sh): a "no", not a stop, so exit 0 and not 130.
s=0; out="$(sleep 3 | timeout --preserve-status -s INT 1 bash -c 'CC_ROOT="$1"; source "$1/lib/common.sh"; source "$1/lib/items.sh"; source "$1/lib/open.sh"; ask_restart 0' sh "$ROOT" 2>&1)" || s=$?
check "Ctrl+C at the question: no restart, exit 0"   [ "$s" -eq 0 ]
check "... says so, on a new line"                   has "$out" "$(printf '\n\n   WARN  Not restarted.')"
# Only with the fake systemctl first in PATH: the real one WOULD restart.
if [ "$(command -v systemctl)" = "$TMP/safe/systemctl" ]; then
    s=0; out="$(printf 'yes\n' | ask_restart 0 2>&1)" || s=$?
    check "answer \"yes\": restarts"                 has "$out" "systemctl reboot (ignored by the tests)"
    check "... after a countdown"                    has "$out" "$(printf '   INFO  Restarting in 2 seconds; press Ctrl+C to stop.\n         2 1 \n   INFO  Restarting ...')"
    check "... exit 0"                               [ "$s" -eq 0 ]
    s=0; out="$(printf 'yes\n' | ask_restart 1 2>&1)" || s=$?
    check "answer \"yes\" after a failed change: exit 1" [ "$s" -eq 1 ]
    # Ctrl+C during the countdown: a "no" too, so no restart and exit 0.
    s=0; out="$(printf 'yes\n' | timeout --preserve-status -s INT 1 bash -c 'CC_ROOT="$1"; source "$1/lib/common.sh"; source "$1/lib/items.sh"; source "$1/lib/open.sh"; RESTART_WAIT=5; ask_restart 0' sh "$ROOT" 2>&1)" || s=$?
    check "Ctrl+C during the countdown: no restart"  hasnt "$out" "systemctl reboot (ignored"
    check "... exit 0"                               [ "$s" -eq 0 ]
    check "... says so, on a new line"               has "$out" "$(printf '\n   WARN  Not restarted.')"
else
    fail "answer \"yes\": not tried, the fake systemctl is not first in PATH"
fi

finish
