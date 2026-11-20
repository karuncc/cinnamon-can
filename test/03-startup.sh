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
run s out env PATH="$TMP/broken-tool:$PATH" "$CC" list
check "broken cinnamon: exit 1, not a silent stop"  [ "$s" -eq 1 ]
check "broken cinnamon: clear message"              has "$out" "  ERROR  This computer cannot run cinnamon-can:"
check "... with the reason below it"                has "$out" "         └ Could not find Cinnamon"

finish
