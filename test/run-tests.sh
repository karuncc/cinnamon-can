#!/usr/bin/env bash
#
# test/run-tests.sh -- checks cinnamon-can without changing this computer.
#
#   bash test/run-tests.sh              every test file
#   bash test/run-tests.sh pager 14     only some: by a word of the file
#                                       name, or by its number
#
# The checks live in test/NN-topic.sh, one file per part of the program
# (test/lib.sh has what they share). This script runs them all at the
# same time, each in a temporary folder of its own, and shows their
# results in order, then the total. A file also runs on its own:
# "bash test/13-pager.sh".
#
# Safe on a normal computer: everything is written into temporary
# folders that are removed at the end (also after Ctrl+C); the real
# backup folder and the computer's settings are never touched. "open" is
# only run in the cases where it stops by itself (nothing differs, only
# system files differ, or right after its summary, since it has no
# terminal to ask in), always with closed input (so it can never read a
# "yes") and with a fake "systemctl" first in PATH (so nothing could
# ever restart the computer). The restart question at the end of "open"
# is tried on its own, with that fake. "script" gives the program a
# terminal where one is needed; "delete" gets its answers that way, and
# only ever deletes cans the tests made in their own folder. What needs
# odd files or folders (files you cannot read, a read-only or FAT backup
# folder) runs the program with a home folder of its own (HOME inside
# the temporary folder), and a stand-in "chmod", "dconf" or pager where
# the real one would not do.
#
# A [SKIP] is a check this computer cannot try (the can has no software
# list, no system files ...); it is counted, never a failure.
#
# NOT covered -- follow the Testing rules in AGENTS.md instead: really
# applying a can ("open" + yes), sudo, language, system files, the real
# restart.
#
# Some checks compare a can with this computer RIGHT NOW (05-live.sh,
# and the "diff CAN" in a few other files); they can fail when a setting
# changes on this computer while the tests run. When one fails, run the
# tests again before looking for a bug.

set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(dirname "$HERE")"

# The same marks as test/lib.sh (and the program): colours only in a
# terminal.
if [ -t 1 ]; then
    T_INFO=$'\e[1;97;44m'"   INFO "$'\e[0m'" "
    T_OK=$'\e[1;30;42m'"     OK "$'\e[0m'" "
    T_ERROR=$'\e[1;97;41m'"  ERROR "$'\e[0m'" "
    T_SUB="         "$'\e[90m'"└"$'\e[0m'" "
    COLOR=1
else
    T_INFO="   INFO  " T_OK="     OK  " T_ERROR="  ERROR  " T_SUB="         └ "
    COLOR=0
fi
checks() { if [ "$1" -eq 1 ]; then printf '1 check'; else printf '%s checks' "$1"; fi; }

# Which files: all of them, or those that match a word given here.
FILES=()
for f in "$HERE"/[0-9][0-9]-*.sh; do
    name="$(basename "$f" .sh)"
    if [ $# -eq 0 ]; then FILES+=("$f"); continue; fi
    for want in "$@"; do
        case "$name" in "$want"-*|*"$want"*) FILES+=("$f"); break ;; esac
    done
done
if [ "${#FILES[@]}" -eq 0 ]; then
    printf '%sNo test file matches "%s". The test files are:\n' "$T_ERROR" "$*"
    for f in "$HERE"/[0-9][0-9]-*.sh; do printf '%s%s\n' "$T_SUB" "$(basename "$f")"; done
    exit 2
fi

# One temporary folder for the whole run: every file makes its own
# folder inside it (through TMPDIR), so whatever is left is removed here.
RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/cinnamon-can-test.XXXXXXXX")"
trap 'chmod -R u+rwX "$RUN_TMP" 2>/dev/null; rm -rf "$RUN_TMP"' EXIT

# Ctrl+C (or kill): every file is told to stop, and each one removes its
# own folder and stops the program it was running; then the rest goes.
PIDS=()
stop() {
    trap '' INT TERM
    local p n alive
    for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill -TERM -- "-$p" 2>/dev/null || true; done
    # Wait until nothing they started runs any more (a program may take a
    # moment to tidy up after itself); after 10 seconds, stop the rest.
    for n in $(seq 100); do
        alive=0
        for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill -0 -- "-$p" 2>/dev/null && alive=1; done
        [ "$alive" -eq 1 ] || break
        sleep 0.1
    done
    for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill -KILL -- "-$p" 2>/dev/null || true; done
    wait 2>/dev/null || true
    # (On stderr, as the program does: it reaches the screen even while
    # the results go into a file.)
    printf '\n%sCancelled; the tests were stopped, and their temporary files removed.\n' "$T_INFO" >&2
    exit 130
}
trap stop INT TERM

VERSION="$(sed -n 's/^CC_VERSION="\(.*\)"$/\1/p' "$ROOT/cinnamon-can")"
if [ "${#FILES[@]}" -eq 1 ]; then
    printf '%sTesting cinnamon-can %s: 1 file ...\n' "$T_INFO" "$VERSION"
else
    printf '%sTesting cinnamon-can %s: %s files at the same time ...\n' "$T_INFO" "$VERSION" "${#FILES[@]}"
fi

# The files that test with a can of this computer all get a copy of the
# same one, sealed here once.
BASE=""
if grep -q '^use_base_can' "${FILES[@]}"; then
    printf '[general]\nbackup_dir = %s\n' "$RUN_TMP/base" > "$RUN_TMP/base.conf"
    if ! "$ROOT/cinnamon-can" -c "$RUN_TMP/base.conf" seal -L "test can" > "$RUN_TMP/base.txt" 2>&1 </dev/null; then
        printf '%sCould not seal a can of this computer to test with:\n' "$T_ERROR"
        sed 's/^/         /' "$RUN_TMP/base.txt"
        exit 1
    fi
    for f in "$RUN_TMP/base"/manual-*.tar.gz.canned; do BASE="$f"; done
fi

# Start them all. Each one gets a process group of its own ("set -m"):
# so it can be stopped as a whole, together with what it runs, and keeps
# Ctrl+C working inside it (the Ctrl+C checks need that).
set -m
for f in "${FILES[@]}"; do
    name="$(basename "$f" .sh)"
    CC_TEST_REPORT="$RUN_TMP/$name.report" CC_TEST_BASE="$BASE" CC_TEST_COLOR="$COLOR" TMPDIR="$RUN_TMP" \
        bash "$f" > "$RUN_TMP/$name.out" 2>&1 </dev/null &
    PIDS+=("$!")
done
set +m

# Their results, in order, as each one is done.
TOTAL=0 FAILED=0 SKIPPED=0
PROBLEMS=() SKIPS=()
i=0
for f in "${FILES[@]}"; do
    name="$(basename "$f" .sh)"
    s=0; wait "${PIDS[i]}" || s=$?
    i=$((i + 1))
    cat "$RUN_TMP/$name.out"
    report="$RUN_TMP/$name.report"
    [ -f "$report" ] || : > "$report"
    while IFS=$'\t' read -r kind a b c; do
        case "$kind" in
            fail) PROBLEMS+=("$name: $a") ;;
            skip) SKIPS+=("$name: $a") ;;
            done) TOTAL=$((TOTAL + a)); FAILED=$((FAILED + b)); SKIPPED=$((SKIPPED + c)) ;;
        esac
    done < "$report"
    # A file that stopped before its last line ran only some checks.
    if ! grep -q '^done' "$report"; then
        PROBLEMS+=("$name: stopped before its end (exit $s)")
        FAILED=$((FAILED + 1))
    fi
done

# The total, with every failed and skipped check named once more.
took="${#FILES[@]} file(s), $SECONDS seconds"
printf '\n'
if [ "${#PROBLEMS[@]}" -eq 0 ]; then
    if [ "$SKIPPED" -eq 0 ]; then
        printf '%sAll %s passed (%s)\n' "$T_OK" "$(checks "$TOTAL")" "$took"
    else
        printf '%sAll %s passed, %s skipped (%s):\n' "$T_OK" "$(checks "$TOTAL")" "$SKIPPED" "$took"
        for p in "${SKIPS[@]}"; do printf '%s%s\n' "$T_SUB" "$p"; done
    fi
    exit 0
fi
printf '%s%s of %s failed (%s):\n' "$T_ERROR" "$FAILED" "$(checks "$TOTAL")" "$took"
for p in "${PROBLEMS[@]}"; do printf '%s%s\n' "$T_SUB" "$p"; done
if [ "$SKIPPED" -gt 0 ]; then
    printf '%s%s skipped:\n' "$T_INFO" "$SKIPPED"
    for p in "${SKIPS[@]}"; do printf '%s%s\n' "$T_SUB" "$p"; done
fi
exit 1
