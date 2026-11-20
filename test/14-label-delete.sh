#!/usr/bin/env bash
#
# test/14-label-delete.sh -- label and delete.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/14-label-delete.sh".

source "$(dirname "$0")/lib.sh"

section "Label"
use_base_can
# A damaged can (not even a tar file), which label refuses and delete
# still deletes.
echo "this is not a tar file" > "$TMP/cans/manual-GRB2-20300101T000003+0000.tar.gz.canned"
# Cans of their own, made from the can of this computer.
U="$TMP/unpack-manage"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
pack "$U" TAG2 10
TAG="$TMP/cans/manual-TAG2-20300101T000010+0000.tar.gz.canned"
# inside CAN -> every file in the can but the manifest, with its
#   permissions, owner, size and time.
inside() { tar -tvzf "$1" | grep -v ' \./manifest\.txt$' | sort; }
before="$(inside "$TAG")"
run s out "$CC" -c "$CONF" label TAG2 "ก่อนอัปเกรด new label"
check "label: exit 0"                                  [ "$s" -eq 0 ]
check "label shows the old label and the new one"      sh -c 'printf "%s" "$1" | grep -qF "         └ Was: test can" && printf "%s" "$1" | grep -qF "         └ Now: ก่อนอัปเกรด new label"' sh "$out"
check "... the can keeps its file name"                [ -f "$TAG" ]
check "... and everything else in it, exactly"         [ "$(inside "$TAG")" = "$before" ]
run s out "$CC" -c "$CONF" peek TAG2
check "peek shows the new label"                       has "$out" "         └ Label: ก่อนอัปเกรด new label"
run s out "$CC" -c "$CONF" label tag2 "ก่อนอัปเกรด new label"
check "the same label again: exit 0, nothing changed"  sh -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -qF "already has this label; nothing was changed."' sh "$s" "$out"
run s out "$CC" -c "$CONF" label TAG2 ""
check "an empty label removes it"                      has "$out" "         └ Now: (none)"
run s out "$CC" -c "$CONF" label TAG2 "$L40"
check "a label of 40 Thai letters is taken"            [ "$s" -eq 0 ]
run s out "$CC" -c "$CONF" label TAG2 "${L40}x"
check "41 characters: exit 1"                          [ "$s" -eq 1 ]
run s out "$CC" -c "$CONF" peek TAG2
check "... and the can keeps its label"                has "$out" "         └ Label: $L40"
run s out "$CC" -c "$CONF" label GRB2 "x"
check "label of a damaged can: exit 1, says why"       sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "damaged"' sh "$s" "$out"
run s out "$CC" -c "$CONF" label TAG2
check "label without a text: exit 1, how to use it"    sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "Usage: cinnamon-can label CAN TEXT"' sh "$s" "$out"


section "Delete"
pack "$U" DRP2 11; pack "$U" DRP3 12
DRP2="$TMP/cans/manual-DRP2-20300101T000011+0000.tar.gz.canned"
DRP3="$TMP/cans/manual-DRP3-20300101T000012+0000.tar.gz.canned"
GRB="$(ls "$TMP/cans"/manual-GRB2-*.tar.gz.canned)"
# A made-up "open" in the log, with DRP2 as its way back.
printf '2030-01-01T00:00:00+0000  host=%s  user=x  cmd=open  can=TAG2  backup=DRP2  system=none  result=applied\n' \
    "$(hostname 2>/dev/null || cat /etc/hostname)" >> "$TMP/cans/cinnamon-can.log"
run s out "$CC" -c "$CONF" delete DRP2 drp3 "$DRP3"
check "delete without a terminal: exit 1"              [ "$s" -eq 1 ]
check "... deletes nothing"                            [ -f "$DRP2" -a -f "$DRP3" ]
check "... says it must be confirmed"                  has "$out" "Command \"delete\" needs to be confirmed in a terminal"
check "... after showing the cans, each one once"      sh -c 'printf "%s" "$1" | grep -qF "   INFO  Cans to be deleted:" && [ "$(printf "%s\n" "$1" | grep -c "└ \[DRP3\]")" -eq 1 ]' sh "$out"
check "... and the way back from the latest open"      has "$out" "   WARN  The can [DRP2] is the way back from the latest open:"
run s out "$CC" -c "$CONF" delete "$CONF"
check "a file that is not a can is never deleted"      sh -c '[ "$1" -eq 1 ] && [ -f "$2" ] && printf "%s" "$3" | grep -qF "Only cans can be deleted"' sh "$s" "$CONF" "$out"
run s out "$CC" -c "$CONF" delete
check "delete without a can: exit 1, how to use it"    sh -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -qF "Usage: cinnamon-can delete CAN"' sh "$s" "$out"
# The answers, in a terminal (only cans in the test folder are deleted).
if command -v script >/dev/null 2>&1; then
    s=0; out="$(in_terminal no -c "$CONF" delete DRP2)" || s=$?
    check "answer \"no\": exit 1, nothing deleted"     [ "$s" -eq 1 -a -f "$DRP2" ]
    check "... says so"                                has "$out" "Cancelled; nothing was deleted."
    s=0; out="$(in_terminal yes -c "$CONF" delete DRP2 DRP3 GRB2 TAG2)" || s=$?
    check "answer \"yes\": exit 0"                     [ "$s" -eq 0 ]
    check "... deletes them all, also a damaged one"   [ ! -e "$DRP2" -a ! -e "$DRP3" -a ! -e "$GRB" -a ! -e "$TAG" ]
    check "... and says so"                            has "$out" "OK  The 4 cans are deleted."
else
    skip '"script" is missing: the answers to "delete" are not tried'
fi
# "list" when the can applied last is gone (deleted above, or by hand).
rm -f "$TAG"
run s out "$CC" -c "$CONF" list
check "list: the can applied last is no longer there"  sh -c 'printf "%s" "$1" | grep -qF "Latest applied on this computer: can [TAG2]" && printf "%s" "$1" | grep -qF "         └ This can is no longer in "' sh "$out"

finish
