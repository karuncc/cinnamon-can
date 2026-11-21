#!/usr/bin/env bash
#
# test/10-control-chars.sh -- text from a can never gives orders to the terminal.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/10-control-chars.sh".

source "$(dirname "$0")/lib.sh"

section "Text from a can never gives orders to the terminal"
use_base_can
# A can edited by hand: control characters (ESC, a carriage return, the
# 8-bit form of ESC [) in its label, its computer name, a setting, a line
# of a file, a file name and a software name -- and a "package name" that
# is a command. Without a terminal the program prints no colours of its
# own, so any control character in what it prints came from the can.
E=$'\e' CR=$'\r' CSI=$'\xc2\x9b'
noctl() { ! grep -q "[$E$CR]" <<< "$1" && ! grep -qF -- "$CSI" <<< "$1"; }
U="$TMP/unpack-ctl"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
sed -i "s/^id[[:space:]]*=.*/id = CTX2/; s/^label[[:space:]]*=.*/label = lab${E}[2Kel/; s/^hostname[[:space:]]*=.*/hostname = host${E}[31mname/" "$U/manifest.txt"
printf '\n[org/cinnamon/sounds]\ncc-ctl-key=%s\n' "'red${E}[31mtext${CR}x'" >> "$U/items/sound/dconf.ini"
F="$(find "$U/items" -path '*/home/*' -type f -name '*.json' | head -n 1)" || true
[ -z "$(tail -c 1 "$F")" ] || echo >> "$F"
echo "cc${E}[2Kline${CSI}31m" >> "$F"
mkdir -p "$U/items/sound/home/.config"
echo hello > "$U/items/sound/home/.config/cc${E}[2Kname.txt"
SW="$(find "$U/items" -name software.txt | head -n 1)" || true
[ -z "$SW" ] || printf '[apps]\ncc-ctl%s[2Kpkg\nx; rm -rf ~\nb.sh\n' "$E" > "$SW"
( cd "$U" && tar -czf "$TMP/cans/manual-CTX2-20300101T000031+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" list
check "list: no control character from a can reaches the screen" noctl "$out"
check "... the label is shown without them"                   has "$out" "lab[2Kel"
run s out "$CC" -c "$CONF" peek CTX2
check "peek: none either"                                     noctl "$out"
check "... the computer name is shown without them"           has "$out" "host[31mname"
run s out "$CC" -c "$CONF" diff CTX2
check "diff: none either"                                     noctl "$out"
check "... a setting's value shows them as plain letters"     has "$out" "'red^[[31mtext^Mx'"
check "... so does a line of a file"                          has "$out" "cc^[[2KlineM-^[31m"
check "... and a file name"                                   has "$out" "~/.config/cc^[[2Kname.txt"
run s out "$CC" -c "$CONF" open CTX2
check "open: none either"                                     noctl "$out"
if [ -n "$SW" ]; then
    check "... a software name shows them as plain letters"   has "$out" "cc-ctl^[[2Kpkg"
    check "... a package name in the command to copy stays one word" has "$out" "'x; rm -rf ~'"
    check "... a name with a [ in it gives no grep error"       hasnt "$out" "grep:"
    check "... a name is looked up as text: b.sh is not bash"  sh -c 'printf "%s\n" "$1" | grep -qE "└ apt +b\.sh +"' sh "$out"
else
    skip 'the can has no software list'
fi
run s out "$CC" -c "$CONF" label CTX2 "new${E}[2Klabel"
run s out "$CC" -c "$CONF" peek CTX2
check "label: control characters are left out of a new label" has "$out" "Label: new[2Klabel"
run s out "$CC" -c "$CONF" peek CTX2 sound
check "peek CAN ITEM: none either"                            noctl "$out"
check "... a setting's value as plain letters"              has "$out" "'red^[[31mtext^Mx'"
check "... and a file name"                                  has "$out" "~/.config/cc^[[2Kname.txt"
# A can that brings an item file with a mistake: the error quotes the
# file, and names it by its place in the can (not the temporary folder).
U="$TMP/unpack-baditem"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
sed -i 's/^id[[:space:]]*=.*/id = BDX2/' "$U/manifest.txt"
printf 'description = An item with a mistake\ndefault = on%s[2Kx\n' "$E" > "$U/catalog/user/cc-bad.item"
( cd "$U" && tar -czf "$TMP/cans/manual-BDX2-20300101T000041+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" peek BDX2
check "a broken item file in a can: exit 1, and says so"     sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "Invalid item file(s) detected:"' sh "$s" "$out"
check "... no control character from it reaches the screen"     noctl "$out"
check "... its bad value shows them as plain letters"       has "$out" 'not "on^[[2Kx"'
check "... and names the file by its place in the can"        has "$out" "         └ • catalog/user/cc-bad.item in the can [BDX2]"

finish
