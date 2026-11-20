#!/usr/bin/env bash
#
# test/05-live.sh -- a can against this computer, right after sealing it.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/05-live.sh".

source "$(dirname "$0")/lib.sh"

section "Against the live computer (a mid-run settings change can fail these)"
use_base_can
run s out "$CC" -c "$CONF" diff "$BASEID"
check "diff right after seal: no differences, exit 0" [ "$s" -eq 0 ]
check "what the can uses always has a heading" \
    sh -c 'printf "%s\n" "$1" | grep -qxE "   INFO  Software, themes and fonts the can uses:|   WARN  Software, themes and fonts the can uses, not installed here:"' sh "$out"
check "... with \"All installed\" under it when nothing is missing" \
    sh -c 'printf "%s\n" "$1" | awk "/^   INFO  Software, themes and fonts the can uses:\$/ { getline; ok = (\$0 == \"         └ All installed on this computer\") } /^   WARN  Software, themes and fonts the can uses/ { ok = 1 } END { exit !ok }"' sh "$out"
run s out "$CC" -c "$CONF" open "$BASEID"
check "open on a matching can stops by itself"        [ "$s" -eq 0 ]
check "open says it already matches"                  has "$out" "settings already match"
# A can that differs ONLY in a system file: open must stop and point at
# the sudo command instead of asking, saving an autocan and restarting.
U="$TMP/unpack-system"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
if [ -d "$U/items/system/root" ]; then
    F="$(find "$U/items/system/root" -type f | head -n 1)" || true
    echo "# changed by the tests" >> "$F"
    sed -i 's/^id[[:space:]]*=.*/id = SYS2/' "$U/manifest.txt"
    ( cd "$U" && tar -czf "$TMP/cans/manual-SYS2-20300101T000001+0000.tar.gz.canned" . )
    run s out "$CC" -c "$CONF" open SYS2
    check "open stops when only system files differ"  [ "$s" -eq 0 ]
    check "open shows the sudo command for them"      has "$out" "       \$ sudo "
    check "... and counts it in the summary"          sh -c 'printf "%s" "$1" | grep -qE "└ ● [1-9][0-9]* system change\(s\) \(only with sudo\)"' sh "$out"
else
    skip 'the can has no system files on this computer'
fi
# A can made by an older version that still holds a setting which is
# never kept now (an item of the user's own could take it then): it is
# not compared and not written back, so the can still matches.
U="$TMP/unpack-never"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
printf "\n[org/x/editor/state/history-entry]\nhistory-search-for=['cc-secret']\n" >> "$U/items/sound/dconf.ini"
sed -i 's/^id[[:space:]]*=.*/id = NEV2/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-NEV2-20300101T000051+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff NEV2
check "an older can's never-kept setting is not compared" [ "$s" -eq 0 ]
check "... nor shown"                                     hasnt "$out" "cc-secret"
run s out "$CC" -c "$CONF" open NEV2
check "... nor written back: open finds nothing to change" has "$out" "settings already match"
run s out "$CC" -c "$CONF" diff "$BASEID" NEV2
check "... nor compared between two cans"                 [ "$s" -eq 0 ]
run s out "$CC" -c "$CONF" diff NEV2 "$BASEID"
check "... either way round"                              [ "$s" -eq 0 ]

finish
