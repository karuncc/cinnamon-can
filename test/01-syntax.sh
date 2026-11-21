#!/usr/bin/env bash
#
# test/01-syntax.sh -- every script is valid bash, and uses only the terminal's own colours.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/01-syntax.sh".

source "$(dirname "$0")/lib.sh"

section "Every script is valid bash"
for f in "$CC" "$ROOT"/lib/*.sh "$ROOT"/test/*.sh; do
    check "bash -n $(basename "$f")" bash -n "$f"
done
# Only the terminal's own colours, so everything follows its palette
# (no 256-colour codes: "38;5;N" or "48;5;N").
check "no 256-colour codes in the program" sh -c '! grep -n "[34]8;5;" "$@"' sh "$CC" "$ROOT"/lib/*.sh
# The pipe rule of AGENTS.md: "head" or "grep -q" stop reading at the
# first line they need, the command before them is cut off, and with
# pipefail the whole line counts as failed -- on long input only, so a
# test with small input would never notice. ("||" is no pipe; comment
# lines do not count.)
check "no pipe into head or grep -q in the program" \
    sh -c '! grep -nE "(^|[^|])\|[[:space:]]*(head|grep[[:space:]]+-[a-zA-Z]*q)" "$@" | grep -vE "^[^:]*:[0-9]+:[[:space:]]*#"' \
    sh "$CC" "$ROOT"/lib/*.sh

finish
