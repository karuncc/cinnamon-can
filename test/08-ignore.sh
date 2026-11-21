#!/usr/bin/env bash
#
# test/08-ignore.sh -- ignore lines: what programs write by themselves does not count.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/08-ignore.sh".

source "$(dirname "$0")/lib.sh"

section "Ignore: what programs write by themselves does not count"
use_base_can
# A can whose items ignore made-up settings (one of each pattern kind)
# and a made-up line in one of its files, plus ONE real change. Only the
# real change may count.
U="$TMP/unpack-ignore"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
printf '\n[org/cinnamon/sounds]\ncc-ign-start-a=1\nb-cc-ign-end=1\ncc-ign-exact=1\ncc-real-key=1\n[org/cinnamon/sounds/cc-ign-folder]\nc=1\n' \
    >> "$U/items/sound/dconf.ini"
printf 'ignore = */cc-ign-start-*  */*-cc-ign-end  */cc-ign-exact  /org/cinnamon/sounds/cc-ign-folder/\n' \
    >> "$U/catalog/builtin/sound.item"
# A home file of an item that has no "ignore" yet gets a made-up line.
R=""
while IFS= read -r F; do
    n="${F#"$U/items/"}"; n="${n%%/*}"
    [ -f "$U/catalog/builtin/$n.item" ] && ! grep -q '^ignore' "$U/catalog/builtin/$n.item" || continue
    R="~/${F#*/home/}"
    [ -z "$(tail -c 1 "$F")" ] || echo >> "$F"     # end the last line first
    echo "cc-noise-line=1" >> "$F"
    printf 'ignore = %s:cc-noise-line=\n' "$R" >> "$U/catalog/builtin/$n.item"
    break
done < <(find "$U/items" -path '*/home/*' -type f)
sed -i 's/^id[[:space:]]*=.*/id = GN22/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-GN22-20300101T000004+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff "$BASEID" GN22
check "the real change still counts: exit 1"            [ "$s" -eq 1 ]
check "... and is shown"                                has "$out" "cc-real-key"
check "ignored settings are not shown"                  sh -c '! printf "%s" "$1" | grep -qE "cc-ign|/c$"' sh "$out"
check "only the real change is counted"                 sh -c 'printf "%s" "$1" | grep -qF "● 1 setting(s) differ" && printf "%s" "$1" | grep -qF "● 0 file(s) differ"' sh "$out"
# A real line after an ignored one: the ignored line is not shown, but the
# real line keeps its real line number.
if [ -n "$R" ]; then
    U="$TMP/unpack-ignore2"; mkdir "$U"
    tar -C "$U" -xzf "$TMP/cans/manual-GN22-20300101T000004+0000.tar.gz.canned"
    F="$(find "$U/items" -path "*/home/${R#\~/}" -type f | head -n 1)" || true
    echo "cc-real-line=1" >> "$F"
    sed -i 's/^id[[:space:]]*=.*/id = GN33/' "$U/manifest.txt"
    ( cd "$U" && tar -czf "$TMP/cans/manual-GN33-20300101T000005+0000.tar.gz.canned" . )
    run s out "$CC" -c "$CONF" diff "$BASEID" GN33
    check "a line after an ignored one keeps its real number" \
        has "$out" "$(printf ' +  %4s   cc-real-line=1' "$(wc -l < "$F")")"
    check "... and the ignored line is not shown"     hasnt "$out" "cc-noise-line"
fi
[ -n "$R" ] || skip 'the can has no home file to add a line to'

# An OLDER can: its own items know nothing of an ignore line that this
# computer's items have now. A copy of the program with one more ignore
# line must not show the setting; the program itself must.
U="$TMP/unpack-older"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
printf '\n[org/cinnamon/sounds]\ncc-later-noise=1\n' >> "$U/items/sound/dconf.ini"
sed -i 's/^id[[:space:]]*=.*/id = KD22/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-KD22-20300101T000005+0000.tar.gz.canned" . )
mkdir "$TMP/prog"; cp -a "$CC" "$ROOT/lib" "$ROOT/items" "$TMP/prog/"
printf 'ignore = */cc-later-noise\n' >> "$TMP/prog/items/sound.item"
run s out "$CC" -c "$CONF" diff "$BASEID" KD22
check "older can, items as they were: it shows"         [ "$s" -eq 1 ]
run s out "$TMP/prog/cinnamon-can" -c "$CONF" diff "$BASEID" KD22
check "older can, this computer ignores it now: exit 0" [ "$s" -eq 0 ]

# Wrong ignore entries are reported, every one of them at once.
mkdir -p "$TMP/items"
printf 'description = test\ndconf = /cc/test/\nignore = */*both-ends* not-a-path ~/no-beginning */fine\n' > "$TMP/items/cc-bad.item"
run s out "$CC" -c "$CONF" list
check "a wrong ignore stops the program: exit 1"        [ "$s" -eq 1 ]
check "... under one header for all item files"         has "$out" "  ERROR  Invalid item file(s) detected:"
check "... naming every wrong entry"                    sh -c 'for w in "*/*both-ends*" not-a-path "~/no-beginning"; do printf "%s" "$1" | grep -qF "\"$w\"" || exit 1; done' sh "$out"
check "... but not the good one"                        hasnt "$out" '"*/fine"'
check "... grouped by file, each problem with its line"  sh -c 'printf "%s" "$1" | grep -qF "         └ • $2/cc-bad.item" && printf "%s" "$1" | grep -qF "           └ L3: Entry"' sh "$out" "$TMP/items"
rm -rf "$TMP/items"

finish
