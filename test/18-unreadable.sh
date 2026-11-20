#!/usr/bin/env bash
#
# test/18-unreadable.sh -- files and folders you cannot read.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/18-unreadable.sh".

source "$(dirname "$0")/lib.sh"

section "Files you cannot read (in a home folder of their own)"
# Your desktop runs as you, so what you cannot read makes no difference
# to it: "seal" leaves it out and names it, "diff" does not compare it,
# and "open" leaves it as it is. All of it in a home folder made for the
# tests (HOME), so the real one is never touched.
UH="$TMP/unread-home" UC="$TMP/unread"
mkdir -p "$UH" "$UC/items"
printf '[general]\nbackup_dir = %s\n' "$UC/cans" > "$UC/test.conf"
cat > "$UC/items/cc-unread.item" <<'EOF'
description = Files for the test of what cannot be read
default     = on
files       = ~/cc-unread/  ~/cc-blocked/inner/file.conf  ~/cc-glob/*.conf
exclude     = ~/cc-unread/skip/
system      = /root/cc-test.conf
EOF
mkdir -p "$UH/cc-unread/closed" "$UH/cc-unread/noenter" "$UH/cc-unread/skip" "$UH/cc-blocked/inner" "$UH/cc-glob"
for f in cc-unread/ok.txt cc-unread/locked.txt cc-unread/closed/in.txt cc-unread/noenter/in.txt \
         cc-unread/skip/in.txt cc-blocked/inner/file.conf cc-glob/a.conf; do
    echo "$f" > "$UH/$f"
done
uh() { env HOME="$UH" XDG_CONFIG_HOME="$UH/.config" XDG_DATA_HOME="$UH/.local/share" PAGER=cat "$CC" -c "$UC/test.conf" "$@"; }
run s out uh seal -L "all readable"
# (/root can never be read; everything in the home folder can, so far)
check "all home files readable: only /root is named"  sh -c 'printf "%s" "$1" | grep -qF "sealed (1 left out, see above):" && ! printf "%s" "$1" | grep -qF "└ ~/"' sh "$out"
UA="$(find "$UC/cans" -name 'manual-*' | head -n 1)" || true
UA="$(basename "$UA" | cut -d- -f2)"
# Now a file without read permission, a folder without any (000) and one
# that cannot be entered (600), a folder on the way to a single file, one
# that a pattern looks in, and a system folder (/root). The folder that
# its item leaves out on purpose (exclude) is not named at all.
chmod 000 "$UH/cc-unread/locked.txt" "$UH/cc-unread/closed" "$UH/cc-unread/skip" "$UH/cc-blocked" "$UH/cc-glob"
chmod 600 "$UH/cc-unread/noenter"
run s out uh seal -L "some unreadable"
check "seal with files you cannot read: exit 0"        [ "$s" -eq 0 ]
check "... names them under a warning"                 has "$out" "   WARN  Left out, since neither you nor your desktop can read them:"
check "... a file, with its item"                      has "$out" "         └ ~/cc-unread/locked.txt  (• cc-unread)"
check "... a folder without permissions"               has "$out" "         └ ~/cc-unread/closed/  (• cc-unread, the whole folder)"
check "... a folder that cannot be entered"            has "$out" "         └ ~/cc-unread/noenter/  (• cc-unread, the whole folder)"
check "... a folder on the way to a file"              has "$out" "         └ ~/cc-blocked/  (• cc-unread, the whole folder)"
check "... the folder a pattern looks in"              has "$out" "         └ ~/cc-glob/  (• cc-unread, the whole folder)"
check "... a system folder"                            has "$out" "         └ /root/  (• cc-unread, the whole folder)"
check "... not what its item excludes"                 hasnt "$out" "skip"
check "... and says so in its last message"            has "$out" "     OK  The can is sealed (6 left out, see above):"
UB="$(find "$UC/cans" -name 'manual-*' ! -name "*-$UA-*" | head -n 1)" || true
inside="$(tar -tzf "$UB")"
check "the can holds what could be read"               has "$inside" "./items/cc-unread/home/cc-unread/ok.txt"
check "... and not the rest"                           hasnt "$inside" "locked.txt"
# Against the can made while all was readable: nothing of it is compared
# (this computer's side is unknown), and "open" would not touch it.
run s out uh diff "$UA"
check "diff: what you cannot read is named"            has "$out" "   WARN  Not compared, since you cannot read them on this computer:"
check "... with its item"                              has "$out" "         └ ~/cc-unread/locked.txt  (• cc-unread)"
check "... not shown as a file open would make"        hasnt "$out" "[NEW]"
check "... so nothing differs"                         has "$out" "No differences."
run s out uh open "$UA"
check "open: left as they are, by name"                has "$out" "   WARN  Left as they are, since you cannot read them:"
check "... with its item"                              has "$out" "         └ ~/cc-unread/closed/  (• cc-unread, the whole folder)"
check "... nothing else differs: it already matches"   has "$out" "already match the can [$UA]"
# A can that also brings a new file: the summary counts only that one,
# and still names the rest as left alone (then stops: no terminal).
U="$TMP/unpack-unread"; mkdir "$U"; tar -C "$U" -xzf "$TMP/unread/cans/manual-$UA-"*
echo "from the can" > "$U/items/cc-unread/home/cc-unread/locked.txt"
echo "new" > "$U/items/cc-unread/home/cc-unread/new.txt"
sed -i 's/^id[[:space:]]*=.*/id = UNR2/' "$U/manifest.txt"
( cd "$U" && tar -czf "$UC/cans/manual-UNR2-20300101T000000+0000.tar.gz.canned" . )
run s out uh open UNR2
check "open: the summary counts only what it may write" has "$out" "         └ ● 1 file(s)"
check "... and names the rest as left alone"            has "$out" "         └ ~/cc-unread/locked.txt  (• cc-unread)"
# A can made by hand may hold a file you cannot read (seal never makes
# one): it is still shown and compared.
( cd "$U" && sed -i 's/^id[[:space:]]*=.*/id = UNR3/' manifest.txt && echo "changed in the can" > items/cc-unread/home/cc-unread/ok.txt \
    && tar -cf "$TMP/unr3.tar" --exclude=./items/cc-unread/home/cc-unread/ok.txt . \
    && tar -rf "$TMP/unr3.tar" --mode=000 ./items/cc-unread/home/cc-unread/ok.txt )
gzip -c "$TMP/unr3.tar" > "$UC/cans/manual-UNR3-20300101T000001+0000.tar.gz.canned"
run s out uh diff "$UA" UNR3
check "two cans, a file in one you cannot read: compared" has "$out" "changed in the can"
run s out uh peek UNR3 cc-unread
check "... and peek shows it"                          has "$out" "changed in the can"
# The wallpaper: its setting is always kept, the image only when you can
# read it. A stand-in "dconf" names the image, so the real settings are
# not even read.
mkdir -p "$TMP/wp-bin"
cat > "$TMP/wp-bin/dconf" <<'EOF'
#!/bin/sh
echo "'file://$CC_WP'"
EOF
chmod +x "$TMP/wp-bin/dconf"
wp() {   # wp IMAGE -> the warning collect_wallpaper leads to, if any
    env PATH="$TMP/wp-bin:$PATH" CC_WP="$1" HOME="$UH" bash -c '
        CC_ROOT="$1"; source "$1/lib/common.sh"; source "$1/lib/items.sh"; source "$1/lib/collect.sh"
        CC_TMP="$2"; rm -rf "$CC_TMP"; mkdir -p "$CC_TMP/item"
        UNREADABLE="$CC_TMP/unreadable.txt"; : > "$UNREADABLE"
        collect_wallpaper "$CC_TMP/item" appearance
        show_unreadable "Left out:"
        [ ! -f "$CC_TMP/item/wallpaper.txt" ] || echo "image kept"' sh "$ROOT" "$TMP/wp-tmp" 2>&1
}
echo picture > "$UH/cc-pic.jpg"
out="$(wp "$UH/cc-pic.jpg")"
check "a wallpaper image you can read is kept"         sh -c '[ "$1" = "image kept" ]' sh "$out"
chmod 000 "$UH/cc-pic.jpg"
out="$(wp "$UH/cc-pic.jpg")"
check "one you cannot read is named"                   has "$out" "         └ ~/cc-pic.jpg  (appearance, the wallpaper image)"
out="$(wp /root/cc-pic.jpg)"
check "... so is one in a folder you cannot enter"     has "$out" "         └ /root/cc-pic.jpg  (appearance, the wallpaper image)"
out="$(wp "$UH/cc-gone.jpg")"
check "... but not one that is gone"                   [ -z "$out" ]
chmod -R u+rwX "$UH"

finish
