#!/usr/bin/env bash
#
# test/run-tests.sh -- checks cinnamon-can without changing this computer.
#
# Run it from anywhere:    bash test/run-tests.sh
#
# Everything is written into one temporary folder that is removed at the
# end; the real backup folder and the computer's settings are never
# touched. "open" is only run in the two cases where it stops by itself
# (nothing differs / only system files differ), always with closed input
# (so it can never wait for an answer) and with a fake "systemctl" first
# in PATH (so nothing could ever restart the computer). The restart
# question at the end of "open" is tried on its own, with that fake.
# "script" gives the program a terminal where one is needed.
# "delete" gets its answers that way, and only ever deletes cans the
# tests made in their own folder.
#
# Covered: every script's syntax, the command line, the start-up errors
# (also with a broken "cinnamon"), seal / list / peek / diff, cans with a
# broken manifest, the diff columns and their order, which item owns
# which setting and which file, what is excluded, ignored and never kept,
# the backup_dir values the config accepts, a PAGER of your own, files you
# cannot read and odd backup folders (both in a home folder of their own),
# long labels and names, label, delete.
#
# NOT covered -- follow the Testing rules in AGENTS.md instead: really
# applying a can ("open" + yes), sudo, language, system files, the real
# restart.
#
# The tests under "against the live computer" compare a can with this
# computer RIGHT NOW; they can fail when a setting changes on this
# computer while the tests run. When one fails, run the script again
# before looking for a bug.

set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
CC="$ROOT/cinnamon-can"
TAB=$'\t'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cinnamon-can-test.XXXXXXXX")"
# (a plain trap, not a cleanup function: lib/common.sh, which the last
# test section loads, has a cleanup function of its own; the files that
# cannot be read are made readable again first, or they would stay)
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

FAILS=0 TESTS=0
pass() { TESTS=$((TESTS + 1)); printf '  ok   %s\n' "$1"; }
fail() { TESTS=$((TESTS + 1)); FAILS=$((FAILS + 1)); printf '  FAIL %s\n' "$1"; }
# check TEXT COMMAND... -> pass or fail by whether the command succeeds.
check()   { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg"; fi; }
# (has: a plain text search inside bash. A pipe into "grep -q" would fail
# on long output: grep stops at the first match, the writer is cut off,
# and with pipefail that counts as a failure.)
has()     { [[ "$1" == *"$2"* ]]; }
hasnt()   { ! has "$1" "$2"; }
section() { printf '\n== %s\n' "$1"; }

# run STATUS_VAR OUTPUT_VAR COMMAND... -> runs the command with closed
#   input and keeps its exit code and everything it printed.
run() {
    local _s=0 _o
    _o="$("${@:3}" </dev/null 2>&1)" || _s=$?
    printf -v "$1" '%s' "$_s"
    printf -v "$2" '%s' "$_o"
}

# The test config: cans go into the temporary folder, items stay at
# their defaults (so hardware and personal are OFF).
CONF="$TMP/test.conf"
printf '[general]\nbackup_dir = %s\n' "$TMP/cans" > "$CONF"

# A fake systemctl, first in PATH for every test: even if a test went
# completely wrong, the computer could not restart.
mkdir -p "$TMP/safe"
printf '#!/bin/sh\necho "systemctl $* (ignored by the tests)"\n' > "$TMP/safe/systemctl"
chmod +x "$TMP/safe/systemctl"
PATH="$TMP/safe:$PATH"


section "every script is valid bash"
for f in "$CC" "$ROOT"/lib/*.sh "${BASH_SOURCE[0]}"; do
    check "bash -n $(basename "$f")" bash -n "$f"
done
# Only the terminal's own colours, so everything follows its palette
# (no 256-colour codes: "38;5;N" or "48;5;N").
check "no 256-colour codes in the program" sh -c '! grep -n "[34]8;5;" "$@"' sh "$CC" "$ROOT"/lib/*.sh


section "command line"
run s out "$CC" --version
check "--version: exit 0"              [ "$s" -eq 0 ]
check "--version names the program"    has "$out" "cinnamon-can "
run s out "$CC" help
check "help: exit 0"                   [ "$s" -eq 0 ]
run s out "$CC" frobnicate
check "unknown command: exit 2"        [ "$s" -eq 2 ]
check "unknown command: message"       has "$out" "  ERROR  Unknown command"
check "... the hint starts under it"   has "$out" "$(printf '\n         Run "cinnamon-can help"')"
# No config yet, and the program in a folder with spaces in its name: the
# commands it shows to copy still work as they are.
SP="$TMP/my programs/cinnamon can"; mkdir -p "$SP/config"
cp -r "$ROOT/cinnamon-can" "$ROOT/lib" "$ROOT/items" "$SP/"
cp "$ROOT/config/example.conf" "$SP/config/"
run s out "$SP/cinnamon-can" list
line="$(printf '%s\n' "$out" | sed -n 's/^       \$ \(cd .*\)$/\1/p')"
check "no config: the cd command quotes a path with spaces"  has "$line" "'"
check "... and works when copied"                             bash -c "$line && test -f config/example.conf"
# A config named by its path, with a space in it: the command to copy
# keeps it, so it finds the same (empty) backup folder.
mkdir -p "$TMP/my conf" "$TMP/no cans yet"
printf '[general]\nbackup_dir = %s\n' "$TMP/no cans yet" > "$TMP/my conf/test.conf"
run s out "$CC" -c "$TMP/my conf/test.conf" list
line="$(printf '%s\n' "$out" | sed -n 's/^       \$ cinnamon-can \(.*\) seal -L "My first can"$/\1/p')"
check "no cans yet: the command keeps the -c it was given"   has "$line" "-c "
run s out bash -c '"$0" '"$line"' list' "$CC"
check "... and that part works when copied"                  has "$out" "none yet"
run s out "$CC" -c no-such-config list
check "missing config: exit 1"         [ "$s" -eq 1 ]
check "missing config: message"        has "$out" "Provided config file not found: config/no-such-config.conf"
# A config with several mistakes: one header, then one line per mistake.
printf '[general]\nbackup_dir = %s\nnot a setting\n[items]\nshell = maybe\n  or not\n[colours]\nx = 1\n' "$TMP/cans" > "$TMP/bad.conf"
run s out "$CC" -c "$TMP/bad.conf" list
check "bad config: exit 1"             [ "$s" -eq 1 ]
check "bad config: one header"         has "$out" "  ERROR  Invalid config file(s) detected:"
check "... the file under it, with a dot" has "$out" "         └ • $TMP/bad.conf"
check "... every mistake under the file"  sh -c 'for w in "L3: Expected" "L5-6: Item" "L7: Unknown section [colours]"; do printf "%s" "$1" | grep -qF "           └ $w" || exit 1; done' sh "$out"
# backup_dir must be ~, ~/... or a full path: anything else would put cans
# in whatever folder the command runs in. Each usual mistake gets a hint,
# and nothing is made (not even by seal, run from a folder of its own).
mkdir -p "$TMP/run here"
bd() {   # bd VALUE COMMAND -> the line about backup_dir, or "ACCEPTED"
    printf '[general]\nbackup_dir = %s\n' "$1" > "$TMP/bd.conf"
    local o
    o="$(cd "$TMP/run here" && "$CC" -c "$TMP/bd.conf" "${2:-list}" </dev/null 2>&1)" && { echo ACCEPTED; return; }
    printf '%s\n' "$o" | sed -n 's/^           └ L2: //p'
}
for v in "~" "~/cc test cans/" "$TMP/cc test cans"; do
    check "backup_dir \"$v\" is fine"                [ "$(bd "$v")" = ACCEPTED ]
done
check "backup_dir \"cans\": a hint"                 [ "$(bd cans)" = 'Setting "backup_dir" must start with ~/ or / (a full path), not "cans"; did you mean ~/cans?' ]
check "... \"./cans\" too"                          [ "$(bd ./cans)" = 'Setting "backup_dir" must start with ~/ or / (a full path), not "./cans"; did you mean ~/cans?' ]
check "... \"../cans\": refused, no guess"          [ "$(bd ../cans)" = 'Setting "backup_dir" must start with ~/ or / (a full path), not "../cans"' ]
check "... \$HOME/cans: write ~/cans"               [ "$(bd '$HOME/cans')" = 'Setting "backup_dir" cannot use $HOME: write ~/cans' ]
check "... \${HOME}/cans too"                       [ "$(bd '${HOME}/cans')" = 'Setting "backup_dir" cannot use $HOME: write ~/cans' ]
check "... another variable: the full path"         [ "$(bd '$XDG_DATA_HOME/cans')" = 'Setting "backup_dir" cannot use variables ("$XDG_DATA_HOME/cans"): write the full path' ]
check "... quotes: not needed, even with spaces"    [ "$(bd '"/tmp/cc my cans"')" = 'Setting "backup_dir" needs no quotes, also with spaces in it: write /tmp/cc my cans' ]
check "... quotes around a mistake: that mistake"   [ "$(bd "'cans'")" = 'Setting "backup_dir" must start with ~/ or / (a full path), not "cans"; did you mean ~/cans?' ]
check "... ~alex/cans: only your own home"          [ "$(bd '~alex/cans')" = 'Setting "backup_dir": ~ stands only for your own home folder (~/...), not "~alex/cans"' ]
check "... a Windows path: refused, no guess"       [ "$(bd 'C:\cans')" = 'Setting "backup_dir" must start with ~/ or / (a full path), not "C:\cans"' ]
check "... a control character is shown as letters" [ "$(bd $'cc\e[31mcans')" = 'Setting "backup_dir" must start with ~/ or / (a full path), not "cc^[[31mcans"; did you mean ~/cc^[[31mcans?' ]
bd cans seal >/dev/null
check "... and seal makes no folder where it runs"  [ -z "$(ls -A "$TMP/run here")" ]


section "start-up checks"
mkdir -p "$TMP/broken-tool"
printf '#!/bin/sh\nexit 1\n' > "$TMP/broken-tool/cinnamon"
chmod +x "$TMP/broken-tool/cinnamon"
run s out env PATH="$TMP/broken-tool:$PATH" "$CC" list
check "broken cinnamon: exit 1, not a silent stop"  [ "$s" -eq 1 ]
check "broken cinnamon: clear message"              has "$out" "  ERROR  This computer cannot run cinnamon-can:"
check "... with the reason below it"                has "$out" "         └ Could not find Cinnamon"


section "seal, list, peek"
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
    printf '  skip the can has no home files\n'
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
    printf '  skip the can has no software list\n'
fi


section "against the live computer (a mid-run settings change can fail these)"
run s out "$CC" -c "$CONF" diff "$BASEID"
check "diff right after seal: no differences, exit 0" [ "$s" -eq 0 ]
check "what the can uses always has a heading" \
    sh -c 'printf "%s\n" "$1" | grep -qxE "   INFO  Software, themes and fonts the can uses:|   WARN  Software, themes and fonts the can uses, not installed here:"' sh "$out"
check "... with \"All installed\" under it when nothing is missing" \
    sh -c 'printf "%s\n" "$1" | awk "/^   INFO  Software, themes and fonts the can uses:\$/ { getline; ok = (\$0 == \"         └ All installed on this computer\") } /^   WARN  Software, themes and fonts the can uses/ { ok = 1 } END { exit !ok }"' sh "$out"
run s out "$CC" -c "$CONF" open "$BASEID"
check "open on a matching can stops by itself"        [ "$s" -eq 0 ]
check "open says it already matches"                  has "$out" "settings already match"
# A can that differs ONLY in a system file: open must stop and point at
# the sudo command instead of asking, saving an autocan and restarting.
U="$TMP/unpack-system"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
if [ -d "$U/items/system/root" ]; then
    F="$(find "$U/items/system/root" -type f | head -n 1)" || true
    echo "# changed by run-tests.sh" >> "$F"
    sed -i 's/^id[[:space:]]*=.*/id = SYS2/' "$U/manifest.txt"
    ( cd "$U" && tar -czf "$TMP/cans/manual-SYS2-20300101T000001+0000.tar.gz.canned" . )
    run s out "$CC" -c "$CONF" open SYS2
    check "open stops when only system files differ"  [ "$s" -eq 0 ]
    check "open shows the sudo command for them"      has "$out" "       \$ sudo "
    check "... and counts it in the summary"          sh -c 'printf "%s" "$1" | grep -qE "└ ● [1-9][0-9]* system change\(s\) \(only with sudo\)"' sh "$out"
else
    printf '  skip the can has no system files on this computer\n'
fi
# A can made by an older version that still holds a setting which is
# never kept now (an item of the user's own could take it then): it is
# not compared and not written back, so the can still matches.
U="$TMP/unpack-never"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
printf "\n[org/x/editor/state/history-entry]\nhistory-search-for=['cc-secret']\n" >> "$U/items/sound/dconf.ini"
sed -i 's/^id[[:space:]]*=.*/id = NEV2/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-NEV2-20300101T000051+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff NEV2
check "an older can's never-kept setting is not compared" [ "$s" -eq 0 ]
check "... nor shown"                                     hasnt "$out" "cc-secret"
run s out "$CC" -c "$CONF" open NEV2
check "... nor written back: open finds nothing to change" has "$out" "settings already match"
run s out "$CC" -c "$CONF" diff "$BASEID" NEV2
check "... nor compared between two cans"                 [ "$s" -eq 0 ]
run s out "$CC" -c "$CONF" diff NEV2 "$BASEID"
check "... either way round"                              [ "$s" -eq 0 ]


section "a can that differs (crafted, so this works on any computer)"
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
    printf '  skip the can has no home files\n'
fi

# Two cans made on different versions: the difference is named.
U="$TMP/unpack-version"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
sed -i 's/^id[[:space:]]*=.*/id = VER2/; s/^cinnamon_version[[:space:]]*=.*/cinnamon_version = 0.0.1/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-VER2-20300101T000006+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff "$BASEID" VER2
check "two cans of different versions: the warning"  has "$out" "The two cans were made on different versions:"
check "... naming both cans"                         has "$out" "Cinnamon $(sed -n 's/^cinnamon_version *= *//p' "$TMP/unpack-differs/manifest.txt") in can [$BASEID], 0.0.1 in can [VER2]"

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
    printf '  skip the can has no settings in other or app-settings\n'
fi

# pack DIR ID NN -> the unpacked can in DIR becomes a can with that ID
#   (NN: two digits that make its file name differ from the others).
pack() {
    sed -i "s/^id[[:space:]]*=.*/id = $2/" "$1/manifest.txt"
    ( cd "$1" && tar -czf "$TMP/cans/manual-$2-20300101T0000$3+0000.tar.gz.canned" . )
}

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
    printf '  skip the can has no home file to move\n'
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
    printf '  skip the can has no language\n'
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
    printf '  skip the can has no gtk-theme setting\n'
fi
if [ -n "$SW" ]; then
    check "a package that is not installed is listed with its item" \
        sh -c 'printf "%s" "$1" | grep -qE "└ apt +cc-no-such-package +$2$"' sh "$out" "$(basename "$(dirname "$SW")")"
    check "... with the command to install it"     has "$out" "       \$ sudo apt install cc-no-such-package"
else
    printf '  skip the can has no software list\n'
fi


section "ignore: what programs write by themselves does not count"
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
[ -n "$R" ] || printf '  skip the can has no home file to add a line to\n'

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


section "broken cans"
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


section "text from a can never gives orders to the terminal"
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
    printf '  skip the can has no software list\n'
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


section "Ctrl+C"
# A "dconf" that never answers keeps the program reading this computer;
# then Ctrl+C arrives ("timeout" sends it to the whole program, as the
# terminal does). The program must say what that means, on a new line.
mkdir -p "$TMP/slow-dconf"
printf '#!/bin/sh\nsleep 20\n' > "$TMP/slow-dconf/dconf"
chmod +x "$TMP/slow-dconf/dconf"
n_before="$(ls "$TMP/cans" | wc -l)"
run s out env PATH="$TMP/slow-dconf:$PATH" timeout --preserve-status -s INT 3 "$CC" -c "$CONF" seal -L "never"
check "Ctrl+C during seal: exit 130"          [ "$s" -eq 130 ]
check "... says that no can was made"         sh -c 'printf "%s\n" "$1" | grep -qxF "   INFO  Cancelled; no can was made."' sh "$out"
check "... and none was, not even a part"     [ "$(ls "$TMP/cans" | wc -l)" -eq "$n_before" ]
run s out env PATH="$TMP/slow-dconf:$PATH" timeout --preserve-status -s INT 3 "$CC" -c "$CONF" diff "$BASEID"
check "Ctrl+C during diff: exit 130"          [ "$s" -eq 130 ]
check "... says that nothing was changed"     sh -c 'printf "%s\n" "$1" | grep -qxF "   INFO  Cancelled; nothing was changed."' sh "$out"


section "long labels and names"
# A label has at most 40 characters; a longer one (from an older can, or
# a manifest changed by hand) is cut where it is shown, in a terminal.
L40="$(printf 'ก%.0s' {1..40})"
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
# in_terminal ANSWER COMMAND... -> runs cinnamon-can in a terminal, with
#   ANSWER typed in; the output without colours. With COLS=N in front,
#   the terminal is N columns wide.
in_terminal() {
    local cmd; cmd="$(printf '%q ' env PAGER=cat "$CC" "${@:2}")"
    [ -z "${COLS:-}" ] || cmd="stty cols $COLS rows 24; $cmd"
    printf '%s\n' "$1" | script -qec "$cmd" /dev/null | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r'
    return "${PIPESTATUS[1]}"
}
if command -v script >/dev/null 2>&1; then
    out="$(in_terminal "" -c "$CONF" list)" || true
    check "... and cut in a terminal"                  has "$out" " A label written by hand that is much lo…"
    # A config file named by hand, too long for the line: cut at the front.
    s=0; out="$(in_terminal "" -c "a-config-file-name-typed-by-hand-that-is-far-too-long-for-the-line" list)" || s=$?
    check "a long config name is cut in a terminal"    sh -c 'printf "%s\n" "$1" | grep -qE "^  ERROR  Provided config file not found: ….{1,38}-line\.conf$"' sh "$out"
    # On 40 columns the message alone nearly fills the line: 10 characters stay.
    s=0; out="$(COLS=40 in_terminal "" -c "a-config-file-name-typed-by-hand-that-is-far-too-long-for-the-line" list)" || s=$?
    check "... also on a very narrow screen"           sh -c 'printf "%s\n" "$1" | grep -qxF "  ERROR  Provided config file not found: …line.conf"' sh "$out"
    # A pager that marks every line it shows: "list" must not use it,
    # "diff" still does (so the check itself can see a pager at work).
    paged() { script -qec "env PAGER='sed s/^/PAGED:/' $(printf '%q ' "$CC" -c "$CONF" "$@")" /dev/null | tr -d '\r'; }
    out="$(paged list)" || true
    check "list in a terminal: printed directly, no pager" hasnt "$out" "PAGED:"
    out="$(paged diff "$BASEID" TES2)" || true
    check "... while diff still uses the pager"            has "$out" "PAGED:"
    # A PAGER of your own (stand-ins, so nothing waits for a key): less
    # gets -R through LESS and keeps the colours; any other pager gets
    # the text without colour codes; one that is not installed is said so.
    # How a pager ends never changes what diff ends with (1: differences).
    mkdir -p "$TMP/pagers"
    printf '#!/bin/sh\necho "LESS=[$LESS] ARGS=[$*]"\nfor f; do :; done\ncat "$f"\n' > "$TMP/pagers/less"
    printf '#!/bin/sh\ncat "$1"\nexit 3\n' > "$TMP/pagers/mypager"
    chmod +x "$TMP/pagers/less" "$TMP/pagers/mypager"
    pg() { script -qec "env $1 PATH=$(printf '%q' "$TMP/pagers:$PATH") $(printf '%q ' "$CC" -c "$CONF" diff "$BASEID" TES2); echo \"exit=\$?\"" /dev/null | tr -d '\r'; }
    out="$(pg '-u LESS PAGER=less')" || true
    check "PAGER=less: it gets -R, F and X like git gives" has "$out" "LESS=[-RFX]"
    check "... so the colours stay"                        has "$out" $'\e['
    check "... and diff ends with 1 (differences)"         has "$out" "exit=1"
    out="$(pg "LESS=-i PAGER='less -S'")" || true
    check "PAGER=less with LESS of your own: -R added"     has "$out" "LESS=[-R -i] ARGS=[-S "
    out="$(pg 'PAGER=mypager')" || true
    check "another pager: the text without colour codes"   sh -c 'printf "%s" "$1" | grep -qF "Summary of the comparison above" && ! printf "%s" "$1" | grep -q "$(printf "\033")"' sh "$out"
    check "... its own exit code does not count"           has "$out" "exit=1"
    out="$(pg 'PAGER=cc-no-such-pager' | sed 's/\x1b\[[0-9;]*m//g')" || true
    check "a pager that is not installed: said so"         has "$out" "   WARN  The pager in PAGER is not installed: cc-no-such-pager"
    check "... and the text follows"                       sh -c 'printf "%s" "$1" | grep -qF "Summary of the comparison above" && printf "%s" "$1" | grep -qF "exit=1"' sh "$out"
else
    printf '  skip "script" is missing: what only shows in a terminal is not tried\n'
fi


section "label"
# Cans of their own, so the cans of the other tests stay as they are.
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


section "delete"
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
    printf '  skip "script" is missing: the answers to "delete" are not tried\n'
fi
# "list" when the can applied last is gone (deleted above, or by hand).
rm -f "$TAG"
run s out "$CC" -c "$CONF" list
check "list: the can applied last is no longer there"  sh -c 'printf "%s" "$1" | grep -qF "Latest applied on this computer: can [TAG2]" && printf "%s" "$1" | grep -qF "         └ This can is no longer in "' sh "$out"


section "what a can must NOT hold (hardware and personal are off)"
U="$TMP/unpack-clean"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
check "no screen-tied settings (text or pointer size)" \
    sh -c 'cd "$1" && ! grep -qE "text-scaling-factor|cursor-size" items/*/dconf.ini' sh "$U"
check "no update/install history of this machine" \
    sh -c 'cd "$1" && ! grep -qE "install-last-run|refresh-last-run|installed-apps" items/*/dconf.ini' sh "$U"
check "no never-kept settings (connect-id ...)" \
    sh -c 'cd "$1" && ! grep -qE "^(connect-id|night-light-last-coordinates|scaling-factor)=" items/*/dconf.ini' sh "$U"
check "no personal or per-machine files" \
    sh -c '! find "$1/items" -path "*enchant*" -o -name "monitors.xml" -o -path "*Templates*" | grep -q .' sh "$U"


section "which item owns what (does not depend on this computer)"
# Load the item files with the program's own code, then push a MADE-UP
# settings dump and file list through the two sorters.
CC_ROOT="$ROOT"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/items.sh"
load_items "$ROOT/items" ""
write_dconf_patterns "$TMP/pat-dconf.txt"
write_file_patterns  "$TMP/pat-files.txt"
cat > "$TMP/fake-dump.txt" <<'EOF'
[org/cinnamon/desktop/interface]
gtk-theme='Mint-Y'
text-scaling-factor=1.25
cursor-size=48
[org/cinnamon/desktop/keybindings/wm]
close=['<Super>q']
[com/linuxmint/updates]
install-last-run=12345
[org/x/warpinator/preferences]
connect-id='SOME-ID'
[org/gnome/terminal/legacy]
theme-variant='dark'
EOF
flat="$(awk -f "$ROOT/lib/dconf.awk" -v flat=1 "$TMP/pat-dconf.txt" "$TMP/fake-dump.txt")"
check "the theme belongs to appearance"        has "$flat" "appearance$TAB/org/cinnamon/desktop/interface/gtk-theme"
check "text size belongs to hardware"          has "$flat" "hardware$TAB/org/cinnamon/desktop/interface/text-scaling-factor"
check "pointer size belongs to hardware"       has "$flat" "hardware$TAB/org/cinnamon/desktop/interface/cursor-size"
check "shortcuts belong to keyboard"           has "$flat" "keyboard$TAB/org/cinnamon/desktop/keybindings/wm/close"
check "unknown app settings fall to app-settings" has "$flat" "app-settings$TAB/org/gnome/terminal/legacy/theme-variant"
check "machine history is excluded"            hasnt "$flat" "install-last-run"
check "never-kept settings are dropped"        hasnt "$flat" "connect-id"
printf '%s\n' \
    "$HOME/.config/gtk-3.0/bookmarks" \
    "$HOME/.config/gtk-3.0/settings.ini" \
    "$HOME/.config/enchant/en.dic" \
    "$HOME/.config/autostart/nvidia-prime.desktop" \
    "$HOME/.config/autostart/something-else.desktop" \
    "$HOME/.config/monitors.xml" \
    "$HOME/.config/fcitx/addon/fcitx-clipboard.conf" > "$TMP/fake-files.txt"
own="$(awk -f "$ROOT/lib/files.awk" "$TMP/pat-files.txt" "$TMP/fake-files.txt")"
check "bookmarks belong to nemo, not appearance"  has "$own" "nemo$TAB$HOME/.config/gtk-3.0/bookmarks"
check "gtk settings belong to appearance"         has "$own" "appearance$TAB$HOME/.config/gtk-3.0/settings.ini"
check "dictionary words belong to personal"       has "$own" "personal$TAB$HOME/.config/enchant/en.dic"
check "nvidia autostart belongs to hardware"      has "$own" "hardware$TAB$HOME/.config/autostart/nvidia-prime.desktop"
check "other autostart belongs to default-apps"   has "$own" "default-apps$TAB$HOME/.config/autostart/something-else.desktop"
check "monitor layout belongs to hardware"        has "$own" "hardware$TAB$HOME/.config/monitors.xml"
check "fcitx add-ons switched on/off belong to keyboard" has "$own" "keyboard$TAB$HOME/.config/fcitx/addon/fcitx-clipboard.conf"


section "what programs write by themselves (the built-in items' ignore lines)"
# A made-up settings dump: noise that programs write by themselves, real
# choices right next to it, and private things. The noise must be ignored
# by the item that takes it, the choices must still count, and the
# private things must not be kept at all.
CC_TMP="$TMP"
cat > "$TMP/noise-dump.txt" <<'EOF'
[org/nemo/window-state]
geometry='1550x879+184+82'
side-pane-view='places'
[org/gnome/libgnomekbd/preview]
x=120
[desktop/ibus/general]
version='1.5.29'
preload-engines=['xkb:us::eng']
[desktop/ibus/panel]
x=10
show-icon-on-systray=true
[org/gtk/settings/file-chooser]
window-size=(1203, 902)
last-folder-uri='file:///tmp'
show-hidden=true
[com/linuxmint/updates]
window-width=790
[org/x/editor/state/window]
size=(650, 500)
[org/x/editor/state/history-entry]
history-search-for=['secret']
[org/x/editor/plugins/filebrowser/on-load]
root='file:///'
virtual-root='file:///tmp'
tree-view=true
enable-remote=true
[org/gnome/evolution-data-server]
migrated=true
[org/gnome/terminal/legacy]
schema-version=3
[io/github/celluloid-player/celluloid]
last-folder-enable=true
[io/github/celluloid-player/celluloid/window-state]
width=800
volume=0.5
[org/cinnamon]
command-history=['some command']
window-effect-speed=1
[org/cinnamon/desktop/keybindings/media-keys]
window-screenshot=['<Alt>Print']
[org/blueman/plugins/recentconns]
recent-connections=['a device']
EOF
write_dconf_patterns "$TMP/pat-noise.txt"
kept="$(awk -f "$ROOT/lib/dconf.awk" -v flat=1 "$TMP/pat-noise.txt" "$TMP/noise-dump.txt")"
# ignored PATH -> success if the item that takes PATH ignores it.
ignored() {
    local n d="${1%/*}" k="${1##*/}"
    n="$(printf '%s\n' "$kept" | awk -F'\t' -v p="$1" '$2 == p { print $1 }')"
    [ -n "$n" ] || return 1
    printf '[%s]\n%s=0\n' "${d#/}" "$k" > "$TMP/one.ini"
    [ -z "$(flat_without_ignored "$TMP/one.ini" "$n")" ]
}
counted() { printf '%s\n' "$kept" | grep -qF "$TAB$1$TAB" && ! ignored "$1"; }
for p in /org/nemo/window-state/geometry /org/gnome/libgnomekbd/preview/x \
         /desktop/ibus/general/version /desktop/ibus/panel/x \
         /org/gtk/settings/file-chooser/window-size /org/gtk/settings/file-chooser/last-folder-uri \
         /com/linuxmint/updates/window-width /org/x/editor/state/window/size \
         /org/x/editor/plugins/filebrowser/on-load/root \
         /org/x/editor/plugins/filebrowser/on-load/virtual-root \
         /org/x/editor/plugins/filebrowser/on-load/tree-view \
         /org/gnome/evolution-data-server/migrated /org/gnome/terminal/legacy/schema-version \
         /io/github/celluloid-player/celluloid/window-state/width; do
    check "noise is ignored: $p" ignored "$p"
done
for p in /org/nemo/window-state/side-pane-view /desktop/ibus/general/preload-engines \
         /desktop/ibus/panel/show-icon-on-systray /org/gtk/settings/file-chooser/show-hidden \
         /io/github/celluloid-player/celluloid/last-folder-enable \
         /io/github/celluloid-player/celluloid/window-state/volume \
         /org/x/editor/plugins/filebrowser/on-load/enable-remote \
         /org/cinnamon/window-effect-speed /org/cinnamon/desktop/keybindings/media-keys/window-screenshot; do
    check "a choice still counts: $p" counted "$p"
done
for p in command-history history-search-for recent-connections; do
    check "private, never kept: $p" hasnt "$kept" "/$p$TAB"
done
# An item of your own that takes whole folders of these apps keeps none
# of the never-kept settings either (the "exclude" of a built-in item
# holds only while that item owns the setting).
mkdir -p "$TMP/own-items"
printf '%s\n' 'description = test' 'default = on' \
    'dconf = /org/x/editor/ /org/cinnamon/ /org/blueman/ /apps/seahorse/' \
    '        /desktop/gnome/crypto/ /com/linuxmint/' > "$TMP/own-items/cc-apps.item"
load_items "$ROOT/items" "$TMP/own-items"
write_dconf_patterns "$TMP/pat-own.txt"
cat > "$TMP/private-dump.txt" <<'EOF'
[org/x/editor/state/history-entry]
history-search-for=['secret']
[org/x/editor/preferences/editor]
scheme='oblivion'
[org/cinnamon]
command-history=['some command']
looking-glass-history=['some code']
[apps/seahorse]
last-search-text='secret'
[org/blueman/plugins/recentconns]
recent-connections=['a device']
[desktop/gnome/crypto/pgp]
last-signer='ABCD'
[com/linuxmint/updates]
install-last-run=12345
refresh-last-run=12345
[com/linuxmint/install]
installed-apps=['an app']
EOF
mine="$(awk -f "$ROOT/lib/dconf.awk" -v flat=1 "$TMP/pat-own.txt" "$TMP/private-dump.txt")"
check "an item of your own takes the app's folder" has "$mine" "cc-apps$TAB/org/x/editor/preferences/editor/scheme"
for p in history-search-for command-history looking-glass-history last-search-text \
         recent-connections last-signer install-last-run refresh-last-run installed-apps; do
    check "... but never keeps: $p" hasnt "$mine" "/$p$TAB"
done
load_items "$ROOT/items" ""
check "fcitx's last input method is ignored" has "${ITEM_IGNORE[keyboard]}" "~/.config/fcitx/profile:IMName="


section "files you cannot read (in a home folder of their own)"
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


section "the backup folder"
# Only a folder the program makes is made private; one you already have
# keeps its permissions (the cans and the log in it are private anyway).
# One you cannot write to is never changed: seal stops before it reads
# anything, open before it asks. (A home folder of its own again.)
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


section "the restart question at the end of open"
# Only the question, with made-up answers: "yes" must call systemctl (the
# fake one; it prints that it was called), anything else must not. The
# number given to ask_restart is what "open" ends with (1: some changes
# could not be made); no answer may change it. After "yes" it counts
# down first; 2 seconds instead of 10 keep the tests short.
source "$ROOT/lib/open.sh"
check "the countdown before a restart is 10 seconds" [ "$RESTART_WAIT" -eq 10 ]
RESTART_WAIT=2
for a in no YES ""; do
    s=0; out="$(printf '%s\n' "$a" | ask_restart 0 2>&1)" || s=$?
    check "answer \"$a\": no restart"                hasnt "$out" "systemctl reboot (ignored"
    check "... says so, with the command to restart"  sh -c 'printf "%s" "$1" | grep -qF "   WARN  Not restarted." && printf "%s" "$1" | grep -qF "       \$ systemctl reboot"' sh "$out"
    check "... exit 0"                               [ "$s" -eq 0 ]
done
s=0; out="$(printf 'no\n' | ask_restart 1 2>&1)" || s=$?
check "answer \"no\" after a failed change: exit 1"  [ "$s" -eq 1 ]
s=0; out="$(ask_restart 0 </dev/null 2>&1)" || s=$?
check "no answer at all (end of input): no restart"  hasnt "$out" "systemctl reboot (ignored"
check "... exit 0"                                   [ "$s" -eq 0 ]
check "the question says why to restart"             has "$out" "   INFO  The desktop shows some changes only after a restart."
check "... and that open programs close unsaved"     has "$out" "         Restarting closes every open program without asking to save."
# Ctrl+C while it waits for the answer ("timeout" sends it, as in the
# Ctrl+C section): a "no", not a stop, so exit 0 and not 130.
s=0; out="$(sleep 3 | timeout --preserve-status -s INT 1 bash -c 'CC_ROOT="$1"; source "$1/lib/common.sh"; source "$1/lib/items.sh"; source "$1/lib/open.sh"; ask_restart 0' sh "$ROOT" 2>&1)" || s=$?
check "Ctrl+C at the question: no restart, exit 0"   [ "$s" -eq 0 ]
check "... says so, on a new line"                   has "$out" "$(printf '\n\n   WARN  Not restarted.')"
# Only with the fake systemctl first in PATH: the real one WOULD restart.
if [ "$(command -v systemctl)" = "$TMP/safe/systemctl" ]; then
    s=0; out="$(printf 'yes\n' | ask_restart 0 2>&1)" || s=$?
    check "answer \"yes\": restarts"                 has "$out" "systemctl reboot (ignored by the tests)"
    check "... after a countdown"                    has "$out" "$(printf '   INFO  Restarting in 2 seconds; press Ctrl+C to stop.\n         2 1 \n   INFO  Restarting ...')"
    check "... exit 0"                               [ "$s" -eq 0 ]
    s=0; out="$(printf 'yes\n' | ask_restart 1 2>&1)" || s=$?
    check "answer \"yes\" after a failed change: exit 1" [ "$s" -eq 1 ]
    # Ctrl+C during the countdown: a "no" too, so no restart and exit 0.
    s=0; out="$(printf 'yes\n' | timeout --preserve-status -s INT 1 bash -c 'CC_ROOT="$1"; source "$1/lib/common.sh"; source "$1/lib/items.sh"; source "$1/lib/open.sh"; RESTART_WAIT=5; ask_restart 0' sh "$ROOT" 2>&1)" || s=$?
    check "Ctrl+C during the countdown: no restart"  hasnt "$out" "systemctl reboot (ignored"
    check "... exit 0"                               [ "$s" -eq 0 ]
    check "... says so, on a new line"               has "$out" "$(printf '\n   WARN  Not restarted.')"
else
    fail "answer \"yes\": not tried, the fake systemctl is not first in PATH"
fi


printf '\n%d test(s), %d failed\n' "$TESTS" "$FAILS"
[ "$FAILS" -eq 0 ]
