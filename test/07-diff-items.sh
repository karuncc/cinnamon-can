#!/usr/bin/env bash
#
# test/07-diff-items.sh -- diff when cans keep things in other items, and what a can uses.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/07-diff-items.sh".

source "$(dirname "$0")/lib.sh"

section "A can whose items differ (crafted, so this works on any computer)"
use_base_can
# Two cans that hold the same setting under different items (one moved it
# into its own user item): both sides are split by the "+" can's items,
# so nothing differs, in both directions.
U="$TMP/unpack-useritem"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
SRC=""
for n in other app-settings; do [ -s "$U/items/$n/dconf.ini" ] && { SRC="$n"; break; }; done
if [ -n "$SRC" ]; then
    # The first setting of that item: its folder, and its line.
    SEC="$(awk '/^\[.*\]$/ { s = $0; next } /=/ { print s; exit }' "$U/items/$SRC/dconf.ini")"
    KEYLINE="$(awk '/^\[.*\]$/ { next } /=/ { print; exit }' "$U/items/$SRC/dconf.ini")"
    KEY="${KEYLINE%%=*}"; FOLDER="${SEC#[}"; FOLDER="${FOLDER%]}"
    awk -v l="$KEYLINE" '$0 != l || done { print; next } { done = 1 }' "$U/items/$SRC/dconf.ini" > "$U/x.ini"
    mv "$U/x.ini" "$U/items/$SRC/dconf.ini"
    mkdir -p "$U/items/cc-own"
    printf '%s\n%s\n' "$SEC" "$KEYLINE" > "$U/items/cc-own/dconf.ini"
    printf 'description = test\ndefault = on\ndconf = /%s/%s\n' "$FOLDER" "$KEY" > "$U/catalog/user/cc-own.item"
    sed -i 's/^id[[:space:]]*=.*/id = USR2/' "$U/manifest.txt"
    ( cd "$U" && tar -czf "$TMP/cans/manual-USR2-20300101T000008+0000.tar.gz.canned" . )
    run s out "$CC" -c "$CONF" diff "$BASEID" USR2
    check "same setting, another item in the + can: no differences" [ "$s" -eq 0 ]
    run s out "$CC" -c "$CONF" diff USR2 "$BASEID"
    check "... and the other way round"                  [ "$s" -eq 0 ]
    check "... without the item the + can does not know" hasnt "$out" "cc-own"
else
    skip 'the can has no settings in other or app-settings'
fi

# The same for a file: the "+" can keeps one home file in its own item.
U="$TMP/unpack-ownfile"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
F="$(find "$U/items" -path '*/home/*' -type f | head -n 1)" || true
if [ -n "$F" ]; then
    REL="${F#"$U"/items/*/home/}"
    mkdir -p "$(dirname "$U/items/cc-own/home/$REL")"
    mv "$F" "$U/items/cc-own/home/$REL"
    printf 'description = test\ndefault = on\nfiles = "~/%s"\n' "$REL" > "$U/catalog/user/cc-own.item"
    pack "$U" OWF2 10
    run s out "$CC" -c "$CONF" diff "$BASEID" OWF2
    check "same file, another item in the + can: no differences" [ "$s" -eq 0 ]
    run s out "$CC" -c "$CONF" diff OWF2 "$BASEID"
    check "... and the other way round"                  [ "$s" -eq 0 ]
else
    skip 'the can has no home file to move'
fi

# What two items take at once (the language, a system file): "seal" gives
# each of them a copy. Two such cans that hold the same must not differ:
# here the language is kept by an own item INSTEAD of the built-in one,
# and a system file by an own item AS WELL AS the built-in one.
U="$TMP/unpack-twice"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
if [ -f "$U/items/language/language.txt" ]; then
    mkdir -p "$U/items/cc-also"
    mv "$U/items/language/language.txt" "$U/items/cc-also/"
    rm -rf "$U/items/language"
    printf 'description = test\ndefault = on\nspecial = language\n' > "$U/catalog/user/cc-also.item"
    F="$(find "$U/items/system/root" -type f 2>/dev/null | head -n 1)" || true
    if [ -n "$F" ]; then
        REL="${F#"$U/items/system/root"}"
        mkdir -p "$(dirname "$U/items/cc-also/root$REL")"
        cp -p "$F" "$U/items/cc-also/root$REL"
        printf 'system = %s\n' "$REL" >> "$U/catalog/user/cc-also.item"
    fi
    pack "$U" TWA2 11
    pack "$U" TWB2 12
    run s out "$CC" -c "$CONF" diff TWA2 TWB2
    check "what two items take at once: no differences"  [ "$s" -eq 0 ]
else
    skip 'the can has no language'
fi

# The "-" can has files in an item the "+" can does not know: they cannot
# be compared, and a warning says so. The other way round they are new
# files -- one of them a link that points nowhere on this computer.
U="$TMP/unpack-leftout"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
mkdir -p "$U/items/cc-extra/home/.config/cc test"
echo hello > "$U/items/cc-extra/home/.config/cc test/a b.conf"
ln -s /cc-no-such-folder/file "$U/items/cc-extra/home/.config/cc test/link"
printf 'description = test\ndefault = on\nfiles = "~/.config/cc test/"\n' > "$U/catalog/user/cc-extra.item"
pack "$U" LFT2 13
run s out "$CC" -c "$CONF" diff LFT2 "$BASEID"
check "files no item of the + can takes: a warning"  has "$out" "   WARN  Not compared: 2 file(s) in can [LFT2] that no item of can [$BASEID] takes:"
check "... with the item they were in"               has "$out" "         └ cc-extra: 2 file(s)"
check "... and the command that shows them, with -c" has "$out" "       \$ cinnamon-can -c ${CONF/#"$HOME"\//\~/} diff $BASEID LFT2"
# The same two cans opened from another folder (a USB stick, say): the
# command names them by their paths, and works when copied.
mkdir -p "$TMP/usb stick"
cp "$TMP/cans/"*-LFT2-*.canned "$TMP/cans/"*-"$BASEID"-*.canned "$TMP/usb stick/"
run s out "$CC" -c "$CONF" diff "$TMP/usb stick/"*-LFT2-*.canned "$TMP/usb stick/"*-"$BASEID"-*.canned
line="$(printf '%s\n' "$out" | sed -n 's/^       \$ cinnamon-can \(.*\)$/\1/p')"
check "cans opened by path: the command names the paths"  has "$line" "usb stick"
run s out bash -c '"$0" '"$line" "$CC"
check "... and works when copied"                         has "$out" "   [NEW] └ • ~/.config/cc test/a b.conf  (+1 | -0)"
run s out "$CC" -c "$CONF" diff "$BASEID" LFT2
check "the other way round they are new files"       has "$out" "   [NEW] └ • ~/.config/cc test/a b.conf  (+1 | -0)"
check "a link that points nowhere: no line count"    sh -c 'printf "%s\n" "$1" | grep -qxF "   [NEW] └ • ~/.config/cc test/link"' sh "$out"
check "... and no error from the shell"              sh -c '! printf "%s" "$1" | grep -qE "No such file|expression expected"' sh "$out"
check "... and no warning, all could be compared"    hasnt "$out" "Not compared"
check "your own item: a dot before its name in the diff" has "$out" "         • cc-extra (your own item)"
run s out "$CC" -c "$CONF" peek LFT2
check "... and in the table of items (peek, seal)" sh -c 'printf "%s\n" "$1" | grep -qE "^         └ • cc-extra +[0-9]+ +[0-9]+"' sh "$out"

# A can that uses a theme and a package this computer does not have: each
# is listed with the item that uses it.
U="$TMP/unpack-missing"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
sed -i 's/^id[[:space:]]*=.*/id = MIS2/' "$U/manifest.txt"
sed -i "s/^gtk-theme=.*/gtk-theme='cc-no-such-theme'/" "$U/items/appearance/dconf.ini" 2>/dev/null || true
SW="$(find "$U/items" -name software.txt | head -n 1)" || true
[ -z "$SW" ] || sed -i '/^\[apps\]$/a cc-no-such-package' "$SW"
( cd "$U" && tar -czf "$TMP/cans/manual-MIS2-20300101T000007+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff "$BASEID" MIS2
check "what is missing: a warning with the same heading" \
    has "$out" "   WARN  Software, themes and fonts the can uses, not installed here:"
if grep -q "cc-no-such-theme" "$U/items/appearance/dconf.ini" 2>/dev/null; then
    check "a theme that is not installed is listed with its item" \
        sh -c 'printf "%s" "$1" | grep -qE "└ theme +cc-no-such-theme +appearance$"' sh "$out"
else
    skip 'the can has no gtk-theme setting'
fi
if [ -n "$SW" ]; then
    check "a package that is not installed is listed with its item" \
        sh -c 'printf "%s" "$1" | grep -qE "└ apt +cc-no-such-package +$2$"' sh "$out" "$(basename "$(dirname "$SW")")"
    check "... with the command to install it"     has "$out" "       \$ sudo apt install cc-no-such-package"
else
    skip 'the can has no software list'
fi

finish
