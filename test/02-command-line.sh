#!/usr/bin/env bash
#
# test/02-command-line.sh -- the command line, the config and its backup_dir.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/02-command-line.sh".

source "$(dirname "$0")/lib.sh"

section "Command line"
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

finish
