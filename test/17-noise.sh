#!/usr/bin/env bash
#
# test/17-noise.sh -- the built-in items' ignore lines, and what is never kept.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/17-noise.sh".

source "$(dirname "$0")/lib.sh"

section "What programs write by themselves (the built-in items' ignore lines)"
# A made-up settings dump: noise that programs write by themselves, real
# choices right next to it, and private things. The noise must be ignored
# by the item that takes it, the choices must still count, and the
# private things must not be kept at all. The item files are loaded with
# the program's own code.
CC_ROOT="$ROOT"
source "$ROOT/lib/common.sh" >/dev/null     # (plain words: see 20-restart.sh)
source "$ROOT/lib/items.sh"
load_items "$ROOT/items" ""
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

finish
