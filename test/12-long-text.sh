#!/usr/bin/env bash
#
# test/12-long-text.sh -- long labels and names, in a file and in a terminal.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/12-long-text.sh".

source "$(dirname "$0")/lib.sh"

section "Long labels and names"
use_base_can
# A label has at most 40 characters; a longer one (from an older can, or
# a manifest changed by hand) is cut where it is shown, in a terminal.
n_before="$(ls "$TMP/cans" | wc -l)"
run s out "$CC" -c "$CONF" seal -L "${L40}x"
check "seal with a label of 41 characters: exit 1"     [ "$s" -eq 1 ]
check "... says how long it is, and the most"          has "$out" "  ERROR  The label is too long: 41 characters (at most 40)"
check "... and no can is made"                         [ "$(ls "$TMP/cans" | wc -l)" -eq "$n_before" ]
U="$TMP/unpack-long"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
sed -i 's/^label[[:space:]]*=.*/label = A label written by hand that is much longer than forty/' "$U/manifest.txt"
pack "$U" WNG2 13
run s out "$CC" -c "$CONF" list
check "a long label is whole in a file"                has "$out" " A label written by hand that is much longer than forty"
# What only shows in a terminal: "script" gives the program one.
if command -v script >/dev/null 2>&1; then
    out="$(in_terminal "" -c "$CONF" list)" || true
    check "... and cut in a terminal"                  has "$out" " A label written by hand that is much lo…"
    # A config file named by hand, too long for the line: cut at the front.
    s=0; out="$(in_terminal "" -c "a-config-file-name-typed-by-hand-that-is-far-too-long-for-the-line" list)" || s=$?
    check "a long config name is cut in a terminal"    sh -c 'printf "%s\n" "$1" | grep -qE "^  ERROR  Provided config file not found: ….{1,38}-line\.conf$"' sh "$out"
    # On 40 columns the message alone nearly fills the line: 10 characters stay.
    s=0; out="$(COLS=40 in_terminal "" -c "a-config-file-name-typed-by-hand-that-is-far-too-long-for-the-line" list)" || s=$?
    check "... also on a very narrow screen"           sh -c 'printf "%s\n" "$1" | grep -qxF "  ERROR  Provided config file not found: …line.conf"' sh "$out"
    # A computer set to a language without UTF-8 (LC_ALL=C): a name in
    # Thai letters is still cut between two letters, never inside one.
    out="$(LC_ALL=C COLS=60 in_terminal "" -c "$(printf 'ก%.0s' {1..60}).conf" list)" || true
    check "... between two letters, whatever the language" sh -c 'printf "%s" "$1" | grep -qF "found: …กก" && printf "%s" "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null' sh "$out"
else
    skip '"script" is missing: what only shows in a terminal is not tried'
fi

finish
