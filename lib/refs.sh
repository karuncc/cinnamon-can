# lib/refs.sh -- find what a can refers to that this computer does not have.
#
# Settings often only NAME something that must exist elsewhere: a theme, a
# font, an applet, an app pinned to the panel. check_refs TREE lists every
# such name that is missing here, so you know what to install. It never
# stops anything; it only reports.
#
# Output lines:  kind<TAB>name<TAB>note
#   kind: theme icons cursor font applet desklet extension app input
#         locale sound apt flatpak program source
#
# Something the tree itself brings along (a theme in ~/.themes, an applet
# in ~/.local/share/cinnamon ...) does not count as missing.

check_refs() {
    local tree="$1" flat="$CC_TMP/refs-settings.txt" v x f
    : > "$flat"
    for f in "$tree"/items/*/dconf.ini; do [ -f "$f" ] && ini_flat "$f" >> "$flat"; done

    # setting PATH -> its value in the tree, without quotes or a type
    #   prefix such as "@as " ('' if unset).
    setting() { awk -F'\t' -v p="$1" '$1 == p { v = $2; sub(/^@[a-z]+ /, "", v); gsub(/^'"'"'|'"'"'$/, "", v); print v; exit }' "$flat"; }
    # in_tree REL -> success if the tree brings home/REL along.
    in_tree() { compgen -G "$tree/items/*/home/$1" >/dev/null; }

    # --- Themes, icons, cursor ---
    for x in /org/cinnamon/desktop/interface/gtk-theme /org/cinnamon/theme/name /org/gnome/desktop/wm/preferences/theme; do
        v="$(setting "$x")"
        [ -n "$v" ] || continue
        [ -d "$HOME/.themes/$v" ] || [ -d "$HOME/.local/share/themes/$v" ] || [ -d "/usr/share/themes/$v" ] \
            || in_tree ".themes/$v" || in_tree ".local/share/themes/$v" \
            || printf 'theme\t%s\t%s\n' "$v" "${x##*/}"
    done
    for x in icon-theme cursor-theme; do
        v="$(setting "/org/cinnamon/desktop/interface/$x")"
        [ -n "$v" ] || continue
        [ -d "$HOME/.icons/$v" ] || [ -d "$HOME/.local/share/icons/$v" ] || [ -d "/usr/share/icons/$v" ] \
            || in_tree ".icons/$v" || in_tree ".local/share/icons/$v" \
            || printf '%s\t%s\t%s\n' "${x%-theme}" "$v" "not installed"
    done

    # --- Fonts ---
    local families="$CC_TMP/refs-fonts.txt"
    { fc-list : family 2>/dev/null | tr ',' '\n'
      { find "$tree"/items/*/home/.fonts "$tree"/items/*/home/.local/share/fonts -type f 2>/dev/null || true; } \
          | while IFS= read -r f; do fc-scan --format '%{family}\n' "$f" 2>/dev/null | tr ',' '\n'; done
    } | sed 's/^ *//; s/ *$//' | sort -u > "$families"
    for x in /org/cinnamon/desktop/interface/font-name /org/gnome/desktop/interface/document-font-name \
             /org/gnome/desktop/interface/monospace-font-name /org/cinnamon/desktop/wm/preferences/titlebar-font; do
        v="$(setting "$x")"
        [ -n "$v" ] || continue
        font_known "$v" "$families" || printf 'font\t%s\t%s\n' "$v" "${x##*/}"
    done

    # --- Applets, desklets, extensions ---
    local kind uuid
    for kind in applet desklet extension; do
        setting "/org/cinnamon/enabled-${kind}s" | tr -d "[]' " | tr ',' '\n' | while IFS= read -r x; do
            [ -n "$x" ] || continue
            case "$kind" in
                applet)    uuid="$(printf '%s' "$x" | cut -d: -f4)" ;;
                desklet)   uuid="$(printf '%s' "$x" | cut -d: -f1)" ;;
                extension) uuid="$x" ;;
            esac
            [ -n "$uuid" ] || continue
            [ -d "/usr/share/cinnamon/${kind}s/$uuid" ] || [ -d "$HOME/.local/share/cinnamon/${kind}s/$uuid" ] \
                || in_tree ".local/share/cinnamon/${kind}s/$uuid" || printf '%s\t%s\t%s\n' "$kind" "$uuid" "not installed"
        done
    done

    # --- Apps the panel, the menu and the default apps point at ---
    {
        setting /org/cinnamon/favorite-apps | tr -d "[]' " | tr ',' '\n' | sed 's/$/\tmenu favourite/'
        for f in "$tree"/items/*/home/.config/cinnamon/spices/grouped-window-list@cinnamon.org/*.json; do
            [ -f "$f" ] && json_list "$f" pinned-apps | sed 's/$/\tpinned to the panel/'
        done
        for f in "$tree"/items/*/home/.config/cinnamon/spices/panel-launchers@cinnamon.org/*.json; do
            [ -f "$f" ] && json_list "$f" launcherList | sed 's/$/\tpanel launcher/'
        done
        for f in "$tree"/items/*/home/.config/mimeapps.list; do
            [ -f "$f" ] && awk -F= '/^\[/ { on = ($0 == "[Default Applications]"); next }
                on && NF == 2 { n = split($2, a, ";"); for (i = 1; i <= n; i++) if (a[i] != "") print a[i] "\tdefault app" }' "$f"
        done
        true
    } | sort -u -t$'\t' -k1,1 | while IFS=$'\t' read -r x v; do
        x="${x%:flatpak}"
        [ -n "$x" ] || continue
        desktop_file_exists "$x" || in_tree ".local/share/applications/$x" || printf 'app\t%s\t%s\n' "$x" "$v"
    done

    # --- Input method ---
    for f in "$tree"/items/*/home/.xinputrc; do
        [ -f "$f" ] || continue
        v="$(awk '/^run_im/ { print $2; exit }' "$f")"
        case "$v" in
            fcitx)  command -v fcitx >/dev/null 2>&1       || printf 'input\tfcitx\tinput method\n' ;;
            fcitx5) command -v fcitx5 >/dev/null 2>&1      || printf 'input\tfcitx5\tinput method\n' ;;
            ibus)   command -v ibus-daemon >/dev/null 2>&1 || printf 'input\tibus\tinput method\n' ;;
        esac
    done

    # --- Languages ---
    local have_locales="$CC_TMP/refs-locales.txt"
    locale -a 2>/dev/null | norm_locale | sort -u > "$have_locales"
    {
        for f in "$tree"/items/*/language.txt; do [ -f "$f" ] && cut -d= -f2 "$f"; done
        for f in "$tree"/items/*/root/etc/default/locale; do [ -f "$f" ] && cut -d= -f2 "$f" | tr -d '"'; done
        true
    } | while IFS= read -r v; do
        [ -n "$v" ] && [ "$v" != "C" ] && [ "$v" != "POSIX" ] || continue
        grep -qx "$(printf '%s\n' "$v" | norm_locale)" "$have_locales" || printf 'locale\t%s\t%s\n' "$v" "not installed"
    done | sort -u

    # --- Sound theme ---
    v="$(setting /org/gnome/desktop/sound/theme-name)"
    if [ -n "$v" ] && [ ! -d "/usr/share/sounds/$v" ] && [ ! -d "$HOME/.local/share/sounds/$v" ]; then
        printf 'sound\t%s\t%s\n' "$v" "sound theme"
    fi

    # --- Software ---
    for f in "$tree"/items/*/software.txt; do
        [ -f "$f" ] || continue
        local installed="$CC_TMP/refs-dpkg.txt" flatpaks="$CC_TMP/refs-flatpak.txt"
        dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null | awk '$NF == "installed" { print $1 }' | sort -u > "$installed"
        { flatpak list --app --columns=application 2>/dev/null || true; } | sort -u > "$flatpaks"
        { software_section "$f" apps; software_section "$f" language-support; } | while IFS= read -r x; do
            grep -qx "$x" "$installed" || printf 'apt\t%s\t%s\n' "$x" "not installed"
        done
        software_section "$f" flatpak | while IFS=$'\t' read -r x v; do
            x="${x%% *}"; [ -n "$x" ] || continue
            grep -qx "$x" "$flatpaks" || printf 'flatpak\t%s\t%s\n' "$x" "${v:-flathub}"
        done
        software_section "$f" local-programs | while IFS= read -r x; do
            [ -e "$x" ] || printf 'program\t%s\t%s\n' "$x" "not here"
        done
        software_section "$f" sources | while IFS=$'\t' read -r x v; do
            [ -e "/etc/apt/sources.list.d/$x" ] || printf 'source\t%s\t%s\n' "$x" "$v"
        done
    done
    return 0
}

# font_known NAME FAMILIES -> success if "Waree Bold 11" (style and size
#   allowed at the end) names an installed font family.
font_known() {
    local name words
    name="$(printf '%s' "$1" | sed 's/ [0-9.]*$//')"
    while [ -n "$name" ]; do
        grep -qixF "$name" "$2" && return 0
        words="${name% *}"
        [ "$words" != "$name" ] || break
        name="$words"
    done
    return 1
}

# desktop_file_exists NAME -> success if an app launcher NAME exists.
desktop_file_exists() {
    local d
    for d in "$HOME/.local/share/applications" /usr/share/applications /usr/local/share/applications \
             /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do
        [ -e "$d/$1" ] && return 0
    done
    return 1
}

# json_list FILE KEY -> the strings in the "value" list of KEY in an applet
#   settings file (enough of JSON for these simple files).
json_list() {
    awk -v key="\"$2\"" '
        index($0, key) { inkey = 1 }
        inkey && /"value"/ { invalue = 1 }
        invalue {
            line = $0
            while (match(line, /"[^"]*"/)) {
                s = substr(line, RSTART + 1, RLENGTH - 2)
                if (s != "value") print s
                line = substr(line, RSTART + RLENGTH)
            }
            if ($0 ~ /\]/) exit
        }' "$1"
}

# norm_locale -> "th_TH.UTF-8" and "th_TH.utf8" both become "th_th".
norm_locale() { tr '[:upper:]' '[:lower:]' | sed 's/\.utf-\{0,1\}8$//; s/@.*$//'; }

# show_missing REFS TREE -> the report, with commands to install software.
show_missing() {
    local refs="$1" tree="$2" kind name note apt="" flat=""
    if [ ! -s "$refs" ]; then
        say "  nothing"
        return 0
    fi
    while IFS=$'\t' read -r kind name note; do
        printf '  %-9s %-36s %s\n' "$kind" "$name" "$note"
        case "$kind" in
            apt)     apt="$apt $name" ;;
            flatpak) flat="${flat}    flatpak install $note $name"$'\n' ;;
        esac
    done < "$refs"
    if [ -n "$apt$flat" ]; then
        say ""
        say "  To install what is missing (check the list first):"
        [ -z "$apt" ] || say "    sudo apt install$apt"
        [ -z "$flat" ] || printf '%s' "$flat"
        if grep -q '^source' "$refs"; then
            say "  Add the missing software sources first (see the \"source\" lines above)."
        fi
    fi
}
