#!/usr/bin/env bash
#
# test/09-broken-cans.sh -- cans that are damaged or have a broken manifest.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/09-broken-cans.sh".

source "$(dirname "$0")/lib.sh"

section "Broken cans"
use_base_can
mkdir -p "$TMP/broken-can"
printf '# cinnamon-can manifest\n[can]\nid = BRK2\n' > "$TMP/broken-can/manifest.txt"
( cd "$TMP/broken-can" && tar -czf "$TMP/cans/manual-BRK2-20300101T000002+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" list
check "list survives a broken manifest: exit 0"  [ "$s" -eq 0 ]
check "list warns about it, with the reason"     has "$out" "└ Its manifest is incomplete"
check "... under the file name, with a dot"      has "$out" "         └ • manual-BRK2-"
check "list still shows the good can"            has "$out" "$BASEID"
check "... and \"Latest:\" on one row only"       [ "$(printf "%s\n" "$out" | grep -c " Latest: └ ")" -eq 1 ]
run s out "$CC" -c "$CONF" peek BRK2
check "peek refuses it: exit 1"                  [ "$s" -eq 1 ]
check "peek says why, the file on its own line"  sh -c 'printf "%s" "$1" | grep -qF "incomplete manifest" && printf "%s" "$1" | grep -qF "         └ • "' sh "$out"
echo "this is not a tar file" > "$TMP/cans/manual-GRB2-20300101T000003+0000.tar.gz.canned"
run s out "$CC" -c "$CONF" peek GRB2
check "peek on a damaged file: exit 1"           [ "$s" -eq 1 ]
check "peek calls it damaged"                    has "$out" "damaged"
run s out "$CC" -c "$CONF" list
check "list names a damaged file too"            has "$out" "└ The file cannot be unpacked"
# A tar.gz that unpacks but has no manifest: every command reads a can
# the same way (check_manifest), so each one gives the same reason.
mkdir -p "$TMP/no-manifest/items/sound"
echo "[org/cinnamon/sounds]" > "$TMP/no-manifest/items/sound/dconf.ini"
( cd "$TMP/no-manifest" && tar -czf "$TMP/cans/manual-NMF2-20300101T000004+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" list
check "a can without a manifest: list says so"   has "$out" "└ It has no manifest"
run s out "$CC" -c "$CONF" peek NMF2
check "... peek too"                             sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "The specified can has no manifest"' sh "$s" "$out"
run s out "$CC" -c "$CONF" label NMF2 "x"
check "... and label"                            sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "The specified can has no manifest"' sh "$s" "$out"

finish
