#!/usr/bin/env bash
#
# test/11-ctrl-c.sh -- what Ctrl+C says, and that it leaves nothing behind.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/11-ctrl-c.sh".

source "$(dirname "$0")/lib.sh"

section "Ctrl+C"
use_base_can
# A "dconf" that never answers keeps the program reading this computer;
# then Ctrl+C arrives ("timeout" sends it to the whole program, as the
# terminal does). The program must say what that means, on a new line.
mkdir -p "$TMP/slow-dconf"
printf '#!/bin/sh\nsleep 20\n' > "$TMP/slow-dconf/dconf"
chmod +x "$TMP/slow-dconf/dconf"
n_before="$(ls "$TMP/cans" | wc -l)"
run s out env PATH="$TMP/slow-dconf:$PATH" timeout --preserve-status -s INT 3 "$CC" -c "$CONF" seal -L "never"
check "Ctrl+C during seal: exit 130"          [ "$s" -eq 130 ]
check "... says that no can was made"         sh -c 'printf "%s\n" "$1" | grep -qxF "   INFO  Cancelled; no can was made."' sh "$out"
check "... and none was, not even a part"     [ "$(ls "$TMP/cans" | wc -l)" -eq "$n_before" ]
run s out env PATH="$TMP/slow-dconf:$PATH" timeout --preserve-status -s INT 3 "$CC" -c "$CONF" diff "$BASEID"
check "Ctrl+C during diff: exit 130"          [ "$s" -eq 130 ]
check "... says that nothing was changed"     sh -c 'printf "%s\n" "$1" | grep -qxF "   INFO  Cancelled; nothing was changed."' sh "$out"

finish
