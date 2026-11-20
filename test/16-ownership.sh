#!/usr/bin/env bash
#
# test/16-ownership.sh -- which item owns which setting and file.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/16-ownership.sh".

source "$(dirname "$0")/lib.sh"

section "Which item owns what (does not depend on this computer)"
# Load the item files with the program's own code, then push a MADE-UP
# settings dump and file list through the two sorters.
CC_ROOT="$ROOT"
source "$ROOT/lib/common.sh" >/dev/null     # (plain words: see 20-restart.sh)
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

finish
