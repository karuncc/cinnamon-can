#!/usr/bin/env bash
#
# test/04-seal-list-peek.sh -- seal, list and peek (also one item in full).
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/04-seal-list-peek.sh".

source "$(dirname "$0")/lib.sh"

section "Seal, list, peek"
run s out "$CC" -c "$CONF" seal -L "test can"
check "seal: exit 0" [ "$s" -eq 0 ]
BASE="$(ls "$TMP/cans"/manual-*.tar.gz.canned 2>/dev/null | head -n 1)" || true
check "seal wrote one can" [ -n "$BASE" ]
check "the can's name has the right shape" \
    sh -c 'basename "$1" | grep -qE "^manual-[2-9A-HJKMNP-Z]{4}-[0-9]{8}T[0-9]{6}[+-][0-9]{4}\.tar\.gz\.canned$"' sh "$BASE"
BASEID="$(basename "$BASE" | cut -d- -f2)"
check "seal was logged" grep -q "cmd=seal" "$TMP/cans/cinnamon-can.log"
check "seal starts with what it seals"  sh -c 'printf "%s" "$1" | grep -qF "   INFO  Sealing the can [$2] ..." && printf "%s" "$1" | grep -qF "         └ Label: test can"' sh "$out" "$BASEID"
check "... lists the items as a tree"  has "$out" "         └ keyboard "
check "seal ends with the ID under OK"   sh -c 'printf "%s" "$1" | grep -qF "     OK  The can is sealed:" && printf "%s" "$1" | grep -qF "         └ ID:     [$2]"' sh "$out" "$BASEID"
check "... the folder (whole, without a terminal) and the file name" sh -c 'printf "%s" "$1" | grep -qF "└ Folder: $(dirname "$2")" && printf "%s" "$1" | grep -qF "└ File:   $(basename "$2")"' sh "$out" "$BASE"
run s out "$CC" -c "$CONF" list
check "list: exit 0"            [ "$s" -eq 0 ]
check "list shows the can ID, in [] without a terminal" has "$out" "[$BASEID]"
check "list marks the newest can \"Latest:\"" has "$out" " Latest: └ [$BASEID] "
check "... instead of \"DESC\" in the heading" hasnt "$out" "DESC"
check "the heading row starts with a node the rows hang from" has "$out" "         • ID     KIND"
check "list shows the label"    has "$out" "test can"
run s out "$CC" -c "$CONF" peek "$BASEID"
check "peek: exit 0"            [ "$s" -eq 0 ]
check "peek lists the items"    has "$out" "keyboard"
# The files of the can, each under the item it is in.
PF="$(tar -tzf "$BASE" | sed -n 's|^\./items/\([^/]*\)/home/\(.*[^/]\)$|\1 \2|p' | head -n 1)" || true
if [ -n "$PF" ]; then
    check "peek lists the files of the can"         has "$out" "           └ ~/${PF#* }"
    check "... under the item they are in"          sh -c 'printf "%s\n" "$1" | awk -v i="         └ $2" -v f="           └ ~/$3" "\$0 == i { under = 1; next } /^         └ / { under = 0 } under && \$0 == f { ok = 1 } END { exit !ok }"' sh "$out" "${PF%% *}" "${PF#* }"
else
    skip 'the can has no home files'
fi
check "... with nothing switched off: no note about it" hasnt "$out" "switched off here"
# An item the can has but this computer switches off: marked in the table.
PN="$(tar -tzf "$BASE" | sed -n 's|^\./items/\([^/]*\)/.*|\1|p' | sort -u | head -n 1)" || true
printf '[general]\nbackup_dir = %s\n\n[items]\n%s = no\n' "$TMP/cans" "$PN" > "$TMP/off.conf"
run s out "$CC" -c "$TMP/off.conf" peek "$BASEID"
check "peek marks an item switched off here"    sh -c 'printf "%s\n" "$1" | grep -qE "^         └ $2 +[0-9]+ +[0-9]+ \(switched off here\)"' sh "$out" "$PN"
check "... and says what that means"            has "$out" "Items switched off here are left alone by diff and open"
# One item in full: its settings with their values, its files with their text.
run s out "$CC" -c "$CONF" peek "$BASEID"
check "peek ends with the command to see one item" sh -c 'printf "%s\n" "$1" | grep -qE "^       \\\$ cinnamon-can -c $2 peek $3 [a-z0-9-]+$"' sh "$out" "${CONF/#"$HOME"\//\~/}" "$BASEID"
if [ -n "$PF" ]; then
    run s out "$CC" -c "$CONF" peek "$BASEID" "${PF%% *}"
    check "peek CAN ITEM: exit 0"                   [ "$s" -eq 0 ]
    check "... names the item"                      has "$out" "   INFO  Item ${PF%% *}: "
    check "... shows each file"                     has "$out" "         └ • ~/${PF#* }  ("
    L1="$(tar -xzOf "$BASE" "./items/${PF%% *}/home/${PF#* }" | head -n 1)" || true
    check "... with its lines, numbered"            has "$out" "       1   $L1"
fi
SP="$(tar -xzOf "$BASE" ./items/keyboard/dconf.ini 2>/dev/null | awk '/^\[/ { s = substr($0, 2, length($0) - 2); next } index($0, "=") { print "/" s "/" substr($0, 1, index($0, "=") - 1); exit }')" || true
if [ -n "$SP" ]; then
    run s out "$CC" -c "$CONF" peek "$BASEID" keyboard
    check "... shows each setting, its value under it" sh -c 'printf "%s\n" "$1" | grep -A1 -xF "         └ $2" | tail -n 1 | grep -qE "^           [^ ]"' sh "$out" "$SP"
fi
run s out "$CC" -c "$CONF" peek "$BASEID" no-such-item
check "peek of an item the can does not have: exit 1" [ "$s" -eq 1 ]
check "... says so, and names the items it has"  sh -c 'printf "%s" "$1" | grep -qF "has no item \"no-such-item\"" && printf "%s" "$1" | grep -qF "Its items: "' sh "$out"
run s out "$CC" -c "$CONF" peek "$BASEID" keyboard extra
check "peek with too many words: how to use it" has "$out" "Usage: cinnamon-can peek CAN [ITEM]"
run s out "$CC" -c "$CONF" peek "$(printf '%s' "$BASEID" | tr '[:upper:]' '[:lower:]')"
check "an ID may be typed in lower case" [ "$s" -eq 0 ]

# peek shows only what is in the can: a can from another Cinnamon version,
# with a package this computer does not have, is not compared with it.
# (It has no label either: "Label: (none)" is shown.)
U="$TMP/unpack-peek"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
sed -i 's/^id[[:space:]]*=.*/id = PEK2/; s/^cinnamon_version[[:space:]]*=.*/cinnamon_version = 0.0.1/; /^label[[:space:]]*=/d' "$U/manifest.txt"
SW="$(find "$U/items" -name software.txt | head -n 1)" || true
[ -z "$SW" ] || printf '[apps]\ncc-no-such-package\n' > "$SW"
( cd "$U" && tar -czf "$TMP/cans/manual-PEK2-20300101T000009+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" peek PEK2
check "peek of another version: exit 0"            [ "$s" -eq 0 ]
check "peek does not compare the versions"         hasnt "$out" "Differs from this computer"
check "... nor what is installed here"             hasnt "$out" "installed on this computer"
check "a can without a label: \"Label: (none)\""   has "$out" "         └ Label: (none)"
if [ -n "$SW" ]; then
    check "peek lists the software names in the can" \
        sh -c 'printf "%s\n" "$1" | grep -qE "└ Apps +cc-no-such-package$"' sh "$out"
    check "... and \"(none)\" for a kind with no names" \
        sh -c 'printf "%s\n" "$1" | grep -qE "└ Flatpak +\(none\)$"' sh "$out"
else
    skip 'the can has no software list'
fi
# A file of yours called software.txt, kept by an item of yours, is not
# the software list (seal keeps that as items/ITEM/software.txt).
U="$TMP/unpack-swfile"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
rm -f "$U"/items/*/software.txt
mkdir -p "$U/items/cc-own/home/Documents"
printf '[apps]\ncc-not-a-list\n' > "$U/items/cc-own/home/Documents/software.txt"
printf 'description = test\ndefault = on\nfiles = ~/Documents/software.txt\n' > "$U/catalog/user/cc-own.item"
pack "$U" SWF2 14
run s out "$CC" -c "$CONF" peek SWF2
check "a file of yours called software.txt is not the software list" hasnt "$out" "cc-not-a-list"

finish
