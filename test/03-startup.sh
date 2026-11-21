#!/usr/bin/env bash
#
# test/03-startup.sh -- what the program says on a computer it cannot run on.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/03-startup.sh".

source "$(dirname "$0")/lib.sh"

section "Start-up checks"
mkdir -p "$TMP/broken-tool"
printf '#!/bin/sh\nexit 1\n' > "$TMP/broken-tool/cinnamon"
chmod +x "$TMP/broken-tool/cinnamon"
run s out env PATH="$TMP/broken-tool:$PATH" "$CC" -c "$CONF" list
check "broken cinnamon: exit 1, not a silent stop"  [ "$s" -eq 1 ]
check "broken cinnamon: clear message"              has "$out" "  ERROR  This computer cannot run cinnamon-can:"
check "... with the reason below it"                has "$out" "         └ Could not find Cinnamon"
# A program it needs is missing: every program this computer has, as
# links in one folder (the only one in PATH), except busctl.
mkdir -p "$TMP/no-busctl"
IFS=: read -r -a dirs <<< "$PATH"
for (( i = ${#dirs[@]} - 1; i >= 0; i-- )); do     # (backwards: the first folder in PATH wins)
    compgen -G "${dirs[i]}/*" >/dev/null || continue
    ln -sfn -t "$TMP/no-busctl" -- "${dirs[i]}"/*
done
rm -f "$TMP/no-busctl/busctl"
run s out env PATH="$TMP/no-busctl" "$CC" -c "$CONF" list
check "a program it needs is missing: exit 1"       [ "$s" -eq 1 ]
check "... and it is named"                         has "$out" "         └ Required program \"busctl\" is missing"

finish
