#!/usr/bin/env bash
#
# test/19-backup-folder.sh -- the backup folder: who may read it, and when it cannot be used.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/19-backup-folder.sh".

source "$(dirname "$0")/lib.sh"

section "The backup folder"
# Only a folder the program makes is made private; one you already have
# keeps its permissions (the cans and the log in it are private anyway).
# One you cannot write to is never changed: seal stops before it reads
# anything, open before it asks. (In a home folder of its own.)
BF="$TMP/bf"; mkdir -p "$BF/home" "$BF/shared" "$BF/ro" "$BF/roparent"
chmod 775 "$BF/shared"; chmod 555 "$BF/ro" "$BF/roparent"
for c in new shared ro roparent notyet; do
    case "$c" in new|notyet|roparent) d="$BF/$c/cans" ;; *) d="$BF/$c" ;; esac
    printf '[general]\nbackup_dir = %s\n' "$d" > "$BF/$c.conf"
done
bf() { env HOME="$BF/home" XDG_CONFIG_HOME="$BF/home/.config" XDG_DATA_HOME="$BF/home/.local/share" PAGER=cat "$CC" -c "$BF/$1.conf" "${@:2}"; }
run s out bf new seal
check "a backup folder the program makes is private"   [ "$(stat -c %a "$BF/new/cans")" = 700 ]
run s out bf shared seal
check "one you already have keeps its permissions"     [ "$(stat -c %a "$BF/shared")" = 775 ]
check "... the can in it is private"                   sh -c 'for f in "$1"/manual-*; do [ "$(stat -c %a "$f")" = 600 ] || exit 1; done' sh "$BF/shared"
check "... and so is the log"                          [ "$(stat -c %a "$BF/shared/cinnamon-can.log")" = 600 ]
run s out bf ro seal
check "a folder you cannot write to: seal stops"       [ "$s" -eq 1 ]
check "... says so, and where it is set"               sh -c 'printf "%s" "$1" | grep -qF "  ERROR  Cannot write to the backup folder $2" && printf "%s" "$1" | grep -qF "(backup_dir in "' sh "$out" "$BF/ro"
check "... before it reads anything"                   hasnt "$out" "Reading this computer"
check "... and leaves the folder as it was"            [ "$(stat -c %a "$BF/ro")" = 555 ]
run s out bf roparent seal
check "a folder that cannot be made: seal says so"     has "$out" "  ERROR  Cannot create the backup folder $BF/roparent/cans"
check "... in its own words"                           hasnt "$out" "mkdir:"
# open shows its summary, then stops before asking: without an autocan
# there would be no way back.
U="$TMP/unpack-bf"; mkdir "$U"; tar -C "$U" -xzf "$(find "$BF/new/cans" -name 'manual-*' | head -n 1)"
mkdir -p "$U/items/sound/home/.config"; echo hi > "$U/items/sound/home/.config/cc-bf.txt"
sed -i 's/^id[[:space:]]*=.*/id = BFO2/' "$U/manifest.txt"
BFO="$BF/new/cans/manual-BFO2-20300101T000000+0000.tar.gz.canned"
( cd "$U" && tar -czf "$BFO" . )
run s out bf ro open "$BFO"
check "open, a folder you cannot write to: the summary" has "$out" "         └ ● 1 file(s)"
check "... then it stops"                              sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "  ERROR  Cannot write to the backup folder $3"' sh "$s" "$out" "$BF/ro"
check "... and says why"                               has "$out" "The autocan (the way back) is saved there first; nothing was changed."
check "... before the question"                        hasnt "$out" "needs to be confirmed"
run s out bf notyet open "$BFO"
check "a folder not made yet: open only checks it"     sh -c 'printf "%s" "$1" | grep -qF "needs to be confirmed" && [ ! -e "$2" ]' sh "$out" "$BF/notyet"
# A file where the folder should be, and a log you cannot write to: said
# plainly, before any work.
echo "not a folder" > "$BF/afile"
printf '[general]\nbackup_dir = %s\n' "$BF/afile" > "$BF/afile.conf"
run s out bf afile seal
check "backup_dir names a file: seal says so"          sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "  ERROR  The backup folder $3 is a file, not a folder"' sh "$s" "$out" "$BF/afile"
chmod 444 "$BF/shared/cinnamon-can.log"
run s out bf shared seal
check "a log you cannot write to: seal stops"          sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "  ERROR  Cannot write to the log $3/cinnamon-can.log"' sh "$s" "$out" "$BF/shared"
check "... before it reads anything"                   hasnt "$out" "Reading this computer"
# A USB stick formatted FAT or exFAT has no permissions: setting them
# fails there (a stand-in "chmod" fails for that folder). Cans are still
# made and can be labelled.
mkdir -p "$BF/shim"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in "%s"*) echo "chmod: Operation not permitted" >&2; exit 1 ;; esac; done\nexec %s "$@"\n' \
    "$BF/fat" "$(command -v chmod)" > "$BF/shim/chmod"
chmod +x "$BF/shim/chmod"
printf '[general]\nbackup_dir = %s\n' "$BF/fat/cans" > "$BF/fat.conf"
run s out env PATH="$BF/shim:$PATH" HOME="$BF/home" XDG_CONFIG_HOME="$BF/home/.config" "$CC" -c "$BF/fat.conf" seal
check "no permissions to set (FAT, exFAT): seal works" sh -c '[ "$1" -eq 0 ] && ls "$2"/manual-* >/dev/null' sh "$s" "$BF/fat/cans"
check "... without the error of chmod"                 hasnt "$out" "Operation not permitted"
FATID="$(basename "$(find "$BF/fat/cans" -name 'manual-*' | head -n 1)" | cut -d- -f2)" || true
run s out env PATH="$BF/shim:$PATH" HOME="$BF/home" XDG_CONFIG_HOME="$BF/home/.config" "$CC" -c "$BF/fat.conf" label "$FATID" "On a stick"
check "... and label works there too"                  sh -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -qF "Now: On a stick"' sh "$s" "$out"
chmod -R u+rwX "$BF"

finish
