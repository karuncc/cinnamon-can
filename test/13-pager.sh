#!/usr/bin/env bash
#
# test/13-pager.sh -- which commands use a pager, and a PAGER of your own.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/13-pager.sh".

source "$(dirname "$0")/lib.sh"

section "The pager: list without one, diff with one, a PAGER of your own"
use_base_can
# A can that differs from it (one more setting), so diff has something
# to show and ends with 1.
U="$TMP/unpack-differs"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
printf '\n[org/cinnamon/sounds]\ncc-test-key=true\n' >> "$U/items/sound/dconf.ini"
pack "$U" TES2 00
# A pager only works in a terminal: "script" gives the program one.
if command -v script >/dev/null 2>&1; then
    # A pager that marks every line it shows: "list" must not use it,
    # "diff" still does (so the check itself can see a pager at work).
    paged() { script -qec "env PAGER='sed s/^/PAGED:/' $(printf '%q ' "$CC" -c "$CONF" "$@")" /dev/null | tr -d '\r'; }
    out="$(paged list)" || true
    check "list in a terminal: printed directly, no pager" hasnt "$out" "PAGED:"
    out="$(paged diff "$BASEID" TES2)" || true
    check "... while diff still uses the pager"            has "$out" "PAGED:"
    # A PAGER of your own (stand-ins, so nothing waits for a key): less
    # gets -R through LESS and keeps the colours; any other pager gets
    # the text without colour codes; one that is not installed is said so.
    # How a pager ends never changes what diff ends with (1: differences).
    mkdir -p "$TMP/pagers"
    printf '#!/bin/sh\necho "LESS=[$LESS] ARGS=[$*]"\nfor f; do :; done\ncat "$f"\n' > "$TMP/pagers/less"
    printf '#!/bin/sh\ncat "$1"\nexit 3\n' > "$TMP/pagers/mypager"
    chmod +x "$TMP/pagers/less" "$TMP/pagers/mypager"
    pg() { script -qec "env $1 PATH=$(printf '%q' "$TMP/pagers:$PATH") $(printf '%q ' "$CC" -c "$CONF" diff "$BASEID" TES2); echo \"exit=\$?\"" /dev/null | tr -d '\r'; }
    out="$(pg '-u LESS PAGER=less')" || true
    check "PAGER=less: it gets -R, F and X like git gives" has "$out" "LESS=[-RFX]"
    check "... so the colours stay"                        has "$out" $'\e['
    check "... and diff ends with 1 (differences)"         has "$out" "exit=1"
    out="$(pg "LESS=-i PAGER='less -S'")" || true
    check "PAGER=less with LESS of your own: -R added"     has "$out" "LESS=[-R -i] ARGS=[-S "
    out="$(pg 'PAGER=mypager')" || true
    check "another pager: the text without colour codes"   sh -c 'printf "%s" "$1" | grep -qF "Summary of the comparison above" && ! printf "%s" "$1" | grep -q "$(printf "\033")"' sh "$out"
    check "... its own exit code does not count"           has "$out" "exit=1"
    out="$(pg 'PAGER=cc-no-such-pager' | sed 's/\x1b\[[0-9;]*m//g')" || true
    check "a pager that is not installed: said so"         has "$out" "   WARN  The pager in PAGER is not installed: cc-no-such-pager"
    check "... and the text follows"                       sh -c 'printf "%s" "$1" | grep -qF "Summary of the comparison above" && printf "%s" "$1" | grep -qF "exit=1"' sh "$out"
else
    skip '"script" is missing: what only shows in a terminal is not tried'
fi

finish
