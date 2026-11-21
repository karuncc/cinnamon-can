#!/usr/bin/env bash
#
# test/06-diff.sh -- diff and the summary of open, with a can that differs.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/06-diff.sh".

source "$(dirname "$0")/lib.sh"

section "A can that differs (crafted, so this works on any computer)"
use_base_can
U="$TMP/unpack-differs"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
printf '\n[org/cinnamon/sounds]\ncc-test-key=true\n' >> "$U/items/sound/dconf.ini"
mkdir -p "$U/items/sound/home/.config"
echo hello > "$U/items/sound/home/.config/cc-test-file.txt"
# One more line at the end of a text file the can has: shown with its number.
T="$(find "$U/items" -path '*/home/*' -type f -name '*.json' | head -n 1)" || true
TN="$(wc -l < "$T")"
[ -z "$(tail -c 1 "$T")" ] || { echo >> "$T"; TN=$((TN + 1)); }
echo "cc-added-line" >> "$T"
sed -i 's/^id[[:space:]]*=.*/id = TES2/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-TES2-20300101T000000+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff "$BASEID" TES2
check "diff with differences: exit 1"                   [ "$s" -eq 1 ]
check "a setting only in one can: (default) on -"       has "$out" " -         (default)"
check "... and its real value on +"                     has "$out" " +         true"
check "the new file is shown: NEW, a dot and its size"  has "$out" "   [NEW] └ • ~/.config/cc-test-file.txt  (+1 | -0)"
check "a changed line shows its real line number"       has "$out" "$(printf ' +  %4s   cc-added-line' $((TN + 1)))"
check "the summary counts them, one row per kind"       sh -c 'for w in "● 1 setting(s) differ" "● 2 file(s) differ" "● 0 system change(s)"; do printf "%s" "$1" | grep -qF "└ $w" || exit 1; done' sh "$out"
check "the two sides are named with - and +"           sh -c 'printf "%s" "$1" | grep -qF "         (-) Can [$2] (Label: test can)" && printf "%s" "$1" | grep -qF "         (+) Can [TES2] (Label: test can)"' sh "$out" "$BASEID"
check "the summary says it sums up the report"         has "$out" "Summary of the comparison above:"
l1="$(printf '%s\n' "$out" | grep -nF -m1 'cc-test-key'      | cut -d: -f1)" || true
l2="$(printf '%s\n' "$out" | grep -nF -m1 'cc-test-file.txt' | cut -d: -f1)" || true
check "inside an item, settings come before files" \
    test -n "$l1" -a -n "$l2" -a "$l1" -lt "$l2"

# "open" shows a summary, not every change. With closed input it cannot
# ask for "yes", so it stops right after the summary: nothing is changed.
run s out "$CC" -c "$CONF" open TES2
check "open: a summary, one row per kind"            sh -c 'for w in "● 1 setting(s)" "● 2 file(s)" "● 0 system change(s) (only with sudo)"; do printf "%s" "$1" | grep -qF "└ $w" || exit 1; done' sh "$out"
check "... not every change"                         hasnt "$out" "cc-added-line"
check "... nothing to delete, so no such warning"    hasnt "$out" "It deletes"
check "... the command that shows every change"      has "$out" "       \$ cinnamon-can -c ${CONF/#"$HOME"\//\~/} diff TES2"
check "... then it stops: no terminal to ask in"     sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "Command \"open\" needs to be confirmed in a terminal"' sh "$s" "$out"
# A can without a file this computer has: open would delete it, and the
# summary names it.
U="$TMP/unpack-deletes"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
G="$(find "$U/items" -path '*/home/*' -type f | head -n 1)" || true
if [ -n "$G" ]; then
    rm "$G"
    sed -i 's/^id[[:space:]]*=.*/id = DEL2/' "$U/manifest.txt"
    ( cd "$U" && tar -czf "$TMP/cans/manual-DEL2-20300101T000021+0000.tar.gz.canned" . )
    run s out "$CC" -c "$CONF" open DEL2
    check "open names each file it would delete"     has "$out" "         └ ~/${G#"$U"/items/*/home/}"
    check "... under a warning that counts them"     has "$out" "   WARN  It deletes 1 file(s) that the can does not have:"
else
    skip 'the can has no home files'
fi

# Two cans made on different versions: the difference is named.
U="$TMP/unpack-version"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
sed -i 's/^id[[:space:]]*=.*/id = VER2/; s/^cinnamon_version[[:space:]]*=.*/cinnamon_version = 0.0.1/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-VER2-20300101T000006+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff "$BASEID" VER2
check "two cans of different versions: the warning"  has "$out" "The two cans were made on different versions:"
check "... naming both cans"                         has "$out" "Cinnamon $(sed -n 's/^cinnamon_version *= *//p' "$TMP/unpack-differs/manifest.txt") in can [$BASEID], 0.0.1 in can [VER2]"

finish
