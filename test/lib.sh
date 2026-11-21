# test/lib.sh -- what every test file shares: a temporary folder of its
# own, the stand-ins that keep this computer safe, the checks, and the
# way results are shown.
#
# A test file (test/NN-topic.sh) starts with
#
#     source "$(dirname "$0")/lib.sh"
#
# then a "section" heading (or more) with its checks, and ends with
# "finish".
# Run all of them with "bash test/run-tests.sh", or one on its own:
# "bash test/13-pager.sh".

set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
CC="$ROOT/cinnamon-can"
TAB=$'\t'

# Everything this file writes goes into one temporary folder, removed at
# the end, also after Ctrl+C. (A plain trap, not a function called
# "cleanup": lib/common.sh, which some files load, has a cleanup function
# of its own. Files that cannot be read are made readable again first,
# or they would stay.)
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cinnamon-can-test.XXXXXXXX")"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM


# ---------------------------------------------------------------------------
# How results look: like the program's own screens (AGENTS.md, "Screen
# output"). A 9-character left column holds the mark, the text starts in
# the right column, and a grey "└" ties each check to its heading:
#
#      INFO  Seal, list, peek
#      [OK] └ seal: exit 0
#    [FAIL] └ list shows the label
#    [SKIP] └ the can has no home files
#
# Colours only in a terminal; the runner, which shows every file's
# results on the terminal, asks for them with CC_TEST_COLOR=1.
# ---------------------------------------------------------------------------

if [ -t 1 ] || [ "${CC_TEST_COLOR:-}" = 1 ]; then
    T_INFO=$'\e[1;97;44m'"   INFO "$'\e[0m'" "       # white on blue, like INFO
    T_OK=$'\e[1;30;42m'"     OK "$'\e[0m'" "         # black on green, like OK
    T_ERROR=$'\e[1;97;41m'"  ERROR "$'\e[0m'" "      # white on red, like ERROR
    T_PASS="    "$'\e[1;32m'"[OK]"$'\e[0m'" "         # green words, like [NEW]
    T_FAIL="  "$'\e[1;31m'"[FAIL]"$'\e[0m'" "         # red words, like [DEL]
    T_SKIP="  "$'\e[1;33m'"[SKIP]"$'\e[0m'" "         # yellow words
    T_SUB=$'\e[90m'"└"$'\e[0m'" "                     # grey, like the program's
else
    T_INFO="   INFO  " T_OK="     OK  " T_ERROR="  ERROR  "
    T_PASS="    [OK] " T_FAIL="  [FAIL] " T_SKIP="  [SKIP] " T_SUB="└ "
fi
T_INDENT="         "

TESTS=0 FAILS=0 SKIPS=0

# section TITLE -> the heading the checks below hang from.
section() { printf '\n%s%s\n' "$T_INFO" "$1"; }

# pass / fail NAME -> one check, and its result.
pass() { TESTS=$((TESTS + 1)); printf '%s%s%s\n' "$T_PASS" "$T_SUB" "$1"; }
fail() {
    TESTS=$((TESTS + 1)); FAILS=$((FAILS + 1))
    printf '%s%s%s\n' "$T_FAIL" "$T_SUB" "$1"
    report fail "$1"
}

# skip WHY -> checks that this computer cannot try (it has no software
#   list, no system files ...): shown and counted, never a failure.
skip() {
    SKIPS=$((SKIPS + 1))
    printf '%s%s%s\n' "$T_SKIP" "$T_SUB" "$1"
    report skip "$1"
}

# report KIND TEXT -> tells the runner (when there is one) about a failed
#   or skipped check, so it can name them all again at the end.
report() { [ -z "${CC_TEST_REPORT:-}" ] || printf '%s\t%s\n' "$1" "$2" >> "$CC_TEST_REPORT"; }

# checks N -> "1 check" or "N checks".
checks() { if [ "$1" -eq 1 ]; then printf '1 check'; else printf '%s checks' "$1"; fi; }

# finish -> the last line of a test file: its totals for the runner, or,
#   run on its own, a line that sums it up. Fails when a check failed.
finish() {
    local skipped=""
    [ "$SKIPS" -eq 0 ] || skipped=", $SKIPS skipped"
    if [ -n "${CC_TEST_REPORT:-}" ]; then
        printf 'done\t%s\t%s\t%s\n' "$TESTS" "$FAILS" "$SKIPS" >> "$CC_TEST_REPORT"
    elif [ "$FAILS" -eq 0 ]; then
        printf '\n%sAll %s passed%s\n' "$T_OK" "$(checks "$TESTS")" "$skipped"
    else
        printf '\n%s%s of %s failed\n' "$T_ERROR" "$FAILS" "$(checks "$TESTS")"
    fi
    [ "$FAILS" -eq 0 ]
}


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

# check TEXT COMMAND... -> pass or fail by whether the command succeeds.
check()   { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg"; fi; }
# (has: a plain text search inside bash. A pipe into "grep -q" would fail
# on long output: grep stops at the first match, the writer is cut off,
# and with pipefail that counts as a failure.)
has()     { [[ "$1" == *"$2"* ]]; }
hasnt()   { ! has "$1" "$2"; }

# run STATUS_VAR OUTPUT_VAR COMMAND... -> runs the command with closed
#   input and keeps its exit code and everything it printed.
run() {
    local _s=0 _o
    _o="$("${@:3}" </dev/null 2>&1)" || _s=$?
    printf -v "$1" '%s' "$_s"
    printf -v "$2" '%s' "$_o"
}

# in_terminal ANSWER COMMAND... -> runs cinnamon-can in a terminal
#   ("script" gives it one), with ANSWER typed in; the output without
#   colours. With COLS=N in front, the terminal is N columns wide.
in_terminal() {
    local cmd; cmd="$(printf '%q ' env PAGER=cat "$CC" "${@:2}")"
    [ -z "${COLS:-}" ] || cmd="stty cols $COLS rows 24; $cmd"
    printf '%s\n' "$1" | script -qec "$cmd" /dev/null | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r'
    return "${PIPESTATUS[1]}"
}


# ---------------------------------------------------------------------------
# The test set-up
# ---------------------------------------------------------------------------

# The test config: cans go into the temporary folder, items stay at
# their defaults (so hardware and personal are OFF).
CONF="$TMP/test.conf"
printf '[general]\nbackup_dir = %s\n' "$TMP/cans" > "$CONF"

# A fake systemctl, first in PATH for every test: even if a test went
# completely wrong, the computer could not restart.
mkdir -p "$TMP/safe"
printf '#!/bin/sh\necho "systemctl $* (ignored by the tests)"\n' > "$TMP/safe/systemctl"
chmod +x "$TMP/safe/systemctl"
PATH="$TMP/safe:$PATH"

# A label of 40 Thai letters: the longest a label may be.
L40="$(printf 'ก%.0s' {1..40})"

# use_base_can -> BASE (its path) and BASEID: a can of this computer,
#   labelled "test can", in this file's backup folder. The runner seals
#   one for all files (so they all test the same can); a file run on its
#   own seals its own.
use_base_can() {
    local f
    mkdir -p "$TMP/cans"
    if [ -n "${CC_TEST_BASE:-}" ]; then
        cp -p "$CC_TEST_BASE" "$TMP/cans/"
    elif ! "$CC" -c "$CONF" seal -L "test can" >"$TMP/base-seal.txt" 2>&1 </dev/null; then
        printf '%sCould not seal a can of this computer to test with:\n' "$T_ERROR"
        sed "s/^/$T_INDENT/" "$TMP/base-seal.txt"
        exit 1
    fi
    for f in "$TMP/cans"/manual-*.tar.gz.canned; do BASE="$f"; break; done
    BASEID="$(basename "$BASE" | cut -d- -f2)"
}

# pack DIR ID NN -> the unpacked can in DIR becomes a can with that ID
#   (NN: two digits that make its file name differ from the others).
pack() {
    sed -i "s/^id[[:space:]]*=.*/id = $2/" "$1/manifest.txt"
    ( cd "$1" && tar -czf "$TMP/cans/manual-$2-20300101T0000$3+0000.tar.gz.canned" . )
}
