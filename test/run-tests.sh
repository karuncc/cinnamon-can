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
# in PATH (so nothing could ever restart the computer).
#
# Covered: every script's syntax, the command line, the start-up errors
# (also with a broken "cinnamon"), seal / list / peek / diff, cans with a
# broken manifest, the diff columns and their order, which item owns
# which setting and which file, what is excluded, ignored and never kept.
#
# NOT covered -- follow the Testing rules in AGENTS.md instead: really
# applying a can ("open" + yes), sudo, language, system files, restart.
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
# test section loads, has a cleanup function of its own)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

FAILS=0 TESTS=0
pass() { TESTS=$((TESTS + 1)); printf '  ok   %s\n' "$1"; }
fail() { TESTS=$((TESTS + 1)); FAILS=$((FAILS + 1)); printf '  FAIL %s\n' "$1"; }
# check TEXT COMMAND... -> pass or fail by whether the command succeeds.
check()   { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg"; fi; }
has()     { printf '%s' "$1" | grep -qF -- "$2"; }
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


section "command line"
run s out "$CC" --version
check "--version: exit 0"              [ "$s" -eq 0 ]
check "--version names the program"    has "$out" "cinnamon-can "
run s out "$CC" help
check "help: exit 0"                   [ "$s" -eq 0 ]
run s out "$CC" frobnicate
check "unknown command: exit 2"        [ "$s" -eq 2 ]
check "unknown command: message"       has "$out" "unknown command"
run s out "$CC" -c no-such-config list
check "missing config: exit 1"         [ "$s" -eq 1 ]
check "missing config: message"        has "$out" "config file not found"


section "start-up checks"
mkdir -p "$TMP/broken-tool"
printf '#!/bin/sh\nexit 1\n' > "$TMP/broken-tool/cinnamon"
chmod +x "$TMP/broken-tool/cinnamon"
run s out env PATH="$TMP/broken-tool:$PATH" "$CC" list
check "broken cinnamon: exit 1, not a silent stop"  [ "$s" -eq 1 ]
check "broken cinnamon: clear message"              has "$out" "could not find Cinnamon"


section "seal, list, peek"
run s out "$CC" -c "$CONF" seal -L "test can"
check "seal: exit 0" [ "$s" -eq 0 ]
BASE="$(ls "$TMP/cans"/manual-*.tar.gz.canned 2>/dev/null | head -n 1)" || true
check "seal wrote one can" [ -n "$BASE" ]
check "the can's name has the right shape" \
    sh -c 'basename "$1" | grep -qE "^manual-[2-9A-HJKMNP-Z]{4}-[0-9]{8}T[0-9]{6}[+-][0-9]{4}\.tar\.gz\.canned$"' sh "$BASE"
BASEID="$(basename "$BASE" | cut -d- -f2)"
check "seal was logged" grep -q "cmd=seal" "$TMP/cans/cinnamon-can.log"
run s out "$CC" -c "$CONF" list
check "list: exit 0"            [ "$s" -eq 0 ]
check "list shows the can"      has "$out" "$BASEID"
check "list shows the label"    has "$out" "test can"
run s out "$CC" -c "$CONF" peek "$BASEID"
check "peek: exit 0"            [ "$s" -eq 0 ]
check "peek lists the items"    has "$out" "keyboard"
run s out "$CC" -c "$CONF" peek "$(printf '%s' "$BASEID" | tr '[:upper:]' '[:lower:]')"
check "an ID may be typed in lower case" [ "$s" -eq 0 ]


section "against the live computer (a mid-run settings change can fail these)"
run s out "$CC" -c "$CONF" diff "$BASEID"
check "diff right after seal: no differences, exit 0" [ "$s" -eq 0 ]
run s out "$CC" -c "$CONF" open "$BASEID"
check "open on a matching can stops by itself"        [ "$s" -eq 0 ]
check "open says it already matches"                  has "$out" "already matches"
# A can that differs ONLY in a system file: open must stop and point at
# the sudo command instead of asking, saving an autocan and restarting.
U="$TMP/unpack-system"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
if [ -d "$U/items/system/root" ]; then
    F="$(find "$U/items/system/root" -type f | head -n 1)"
    echo "# changed by run-tests.sh" >> "$F"
    sed -i 's/^id[[:space:]]*=.*/id = SYS2/' "$U/manifest.txt"
    ( cd "$U" && tar -czf "$TMP/cans/manual-SYS2-20300101T000001+0000.tar.gz.canned" . )
    run s out "$CC" -c "$CONF" open SYS2
    check "open stops when only system files differ"  [ "$s" -eq 0 ]
    check "open shows the sudo command for them"      has "$out" "sudo "
else
    printf '  skip the can has no system files on this computer\n'
fi


section "a can that differs (crafted, so this works on any computer)"
U="$TMP/unpack-differs"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
printf '\n[org/cinnamon/sounds]\ncc-test-key=true\n' >> "$U/items/sound/dconf.ini"
mkdir -p "$U/items/sound/home/.config"
echo hello > "$U/items/sound/home/.config/cc-test-file.txt"
sed -i 's/^id[[:space:]]*=.*/id = TES2/' "$U/manifest.txt"
( cd "$U" && tar -czf "$TMP/cans/manual-TES2-20300101T000000+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" diff "$BASEID" TES2
check "diff with differences: exit 1"                   [ "$s" -eq 1 ]
check "a setting only in one can: (default) on -"       has "$out" "-(default)"
check "... and its real value on +"                     has "$out" "+true"
check "the new file is shown"                           has "$out" "cc-test-file.txt"
check "the summary counts them"                         has "$out" "1 setting(s), 1 file(s), 0 system change(s)"
l1="$(printf '%s\n' "$out" | grep -nF -m1 'cc-test-key'      | cut -d: -f1)" || true
l2="$(printf '%s\n' "$out" | grep -nF -m1 'cc-test-file.txt' | cut -d: -f1)" || true
check "inside an item, settings come before files" \
    test -n "$l1" -a -n "$l2" -a "$l1" -lt "$l2"


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
check "only the real change is counted"                 has "$out" "1 setting(s), 0 file(s)"
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
check "... naming every wrong entry"                    sh -c 'for w in "*/*both-ends*" not-a-path "~/no-beginning"; do printf "%s" "$1" | grep -qF "\"$w\"" || exit 1; done' sh "$out"
check "... but not the good one"                        hasnt "$out" '"*/fine"'
rm -rf "$TMP/items"


section "broken cans"
mkdir -p "$TMP/broken-can"
printf '# cinnamon-can manifest\n[can]\nid = BRK2\n' > "$TMP/broken-can/manifest.txt"
( cd "$TMP/broken-can" && tar -czf "$TMP/cans/manual-BRK2-20300101T000002+0000.tar.gz.canned" . )
run s out "$CC" -c "$CONF" list
check "list survives a broken manifest: exit 0"  [ "$s" -eq 0 ]
check "list warns about it"                      has "$out" "broken manifest"
check "list still shows the good can"            has "$out" "$BASEID"
run s out "$CC" -c "$CONF" peek BRK2
check "peek refuses it: exit 1"                  [ "$s" -eq 1 ]
check "peek says why"                            has "$out" "broken manifest"
echo "this is not a tar file" > "$TMP/cans/manual-GRB2-20300101T000003+0000.tar.gz.canned"
run s out "$CC" -c "$CONF" peek GRB2
check "peek on a damaged file: exit 1"           [ "$s" -eq 1 ]
check "peek calls it damaged"                    has "$out" "damaged"


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
    "$HOME/.config/monitors.xml" > "$TMP/fake-files.txt"
own="$(awk -f "$ROOT/lib/files.awk" "$TMP/pat-files.txt" "$TMP/fake-files.txt")"
check "bookmarks belong to nemo, not appearance"  has "$own" "nemo$TAB$HOME/.config/gtk-3.0/bookmarks"
check "gtk settings belong to appearance"         has "$own" "appearance$TAB$HOME/.config/gtk-3.0/settings.ini"
check "dictionary words belong to personal"       has "$own" "personal$TAB$HOME/.config/enchant/en.dic"
check "nvidia autostart belongs to hardware"      has "$own" "hardware$TAB$HOME/.config/autostart/nvidia-prime.desktop"
check "other autostart belongs to default-apps"   has "$own" "default-apps$TAB$HOME/.config/autostart/something-else.desktop"
check "monitor layout belongs to hardware"        has "$own" "hardware$TAB$HOME/.config/monitors.xml"


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
         /org/gnome/evolution-data-server/migrated /org/gnome/terminal/legacy/schema-version \
         /io/github/celluloid-player/celluloid/window-state/width; do
    check "noise is ignored: $p" ignored "$p"
done
for p in /org/nemo/window-state/side-pane-view /desktop/ibus/general/preload-engines \
         /desktop/ibus/panel/show-icon-on-systray /org/gtk/settings/file-chooser/show-hidden \
         /io/github/celluloid-player/celluloid/last-folder-enable \
         /io/github/celluloid-player/celluloid/window-state/volume \
         /org/cinnamon/window-effect-speed /org/cinnamon/desktop/keybindings/media-keys/window-screenshot; do
    check "a choice still counts: $p" counted "$p"
done
for p in command-history history-search-for recent-connections; do
    check "private, never kept: $p" hasnt "$kept" "/$p$TAB"
done
check "fcitx's last input method is ignored" has "${ITEM_IGNORE[keyboard]}" "~/.config/fcitx/profile:IMName="


printf '\n%d test(s), %d failed\n' "$TESTS" "$FAILS"
[ "$FAILS" -eq 0 ]
