# lib/refs.sh -- find what a can refers to that this computer does not have.
#
# Settings often only NAME something that must exist elsewhere: a theme, a
# font, an applet, an app pinned to the panel. check_refs TREE lists every
# such name that is not installed here, so you know what to install. It
# never stops anything; it only reports.
#
# Output lines:  kind<TAB>name<TAB>item[<TAB>flatpak remote]
#   kind: theme icons cursor font applet desklet extension app input
#         locale sound apt flatpak program source
#   item: the item of the can whose settings or files name it
#
# Something the tree itself brings along (a theme in ~/.themes, an applet
# in ~/.local/share/cinnamon ...) does not count as missing.

check_refs() {
    local tree="$1" flat="$CC_TMP/refs-settings.txt" v x f n
    # setting PATH -> its value in the tree, without quotes or a type
    #   prefix such as "@as " ('' if unset).
    setting() { awk -F'\t' -v p="$1" '$2 == p { v = $3; sub(/^@[a-z]+ /, "", v); gsub(/^'"'"'|'"'"'$/, "", v); print v; exit }' "$flat"; }
    # setting_item PATH -> the item that holds that setting.
    setting_item() { awk -F'\t' -v p="$1" '$2 == p { print $1; exit }' "$flat"; }
    # item_of FILE -> the item a file of the tree belongs to.
    item_of() { n="${1#"$tree"/items/}"; printf '%s' "${n%%/*}"; }
    # in_tree REL -> success if the tree brings home/REL along.
    in_tree() { compgen -G "$tree/items/*/home/$1" >/dev/null; }

    : > "$flat"
    for f in "$tree"/items/*/dconf.ini; do [ -f "$f" ] && ini_flat "$f" "$(item_of "$f")" >> "$flat"; done

    # --- Themes, icons, cursor ---
    for x in /org/cinnamon/desktop/interface/gtk-theme /org/cinnamon/theme/name /org/gnome/desktop/wm/preferences/theme; do
        v="$(setting "$x")"
        [ -n "$v" ] || continue
        [ -d "$HOME/.themes/$v" ] || [ -d "$HOME/.local/share/themes/$v" ] || [ -d "/usr/share/themes/$v" ] \
            || in_tree ".themes/$v" || in_tree ".local/share/themes/$v" \
            || printf 'theme\t%s\t%s\n' "$v" "$(setting_item "$x")"
    done
    for x in icon-theme cursor-theme; do
        v="$(setting "/org/cinnamon/desktop/interface/$x")"
        [ -n "$v" ] || continue
        [ -d "$HOME/.icons/$v" ] || [ -d "$HOME/.local/share/icons/$v" ] || [ -d "/usr/share/icons/$v" ] \
            || in_tree ".icons/$v" || in_tree ".local/share/icons/$v" \
            || printf '%s\t%s\t%s\n' "${x%-theme}" "$v" "$(setting_item "/org/cinnamon/desktop/interface/$x")"
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
        font_known "$v" "$families" || printf 'font\t%s\t%s\n' "$v" "$(setting_item "$x")"
    done

    # --- Applets, desklets, extensions ---
    local kind uuid where
    for kind in applet desklet extension; do
        where="$(setting_item "/org/cinnamon/enabled-${kind}s")"
        setting "/org/cinnamon/enabled-${kind}s" | tr -d "[]' " | tr ',' '\n' | while IFS= read -r x; do
            [ -n "$x" ] || continue
            case "$kind" in
                applet)    uuid="$(printf '%s' "$x" | cut -d: -f4)" ;;
                desklet)   uuid="$(printf '%s' "$x" | cut -d: -f1)" ;;
                extension) uuid="$x" ;;
            esac
            [ -n "$uuid" ] || continue
            [ -d "/usr/share/cinnamon/${kind}s/$uuid" ] || [ -d "$HOME/.local/share/cinnamon/${kind}s/$uuid" ] \
                || in_tree ".local/share/cinnamon/${kind}s/$uuid" || printf '%s\t%s\t%s\n' "$kind" "$uuid" "$where"
        done
    done

    # --- Apps the panel, the menu and the default apps point at ---
    {
        where="$(setting_item /org/cinnamon/favorite-apps)"
        setting /org/cinnamon/favorite-apps | tr -d "[]' " | tr ',' '\n' | sed "s/\$/\t$where/"
        for f in "$tree"/items/*/home/.config/cinnamon/spices/grouped-window-list@cinnamon.org/*.json; do
            [ -f "$f" ] && json_list "$f" pinned-apps | sed "s/\$/\t$(item_of "$f")/"
        done
        for f in "$tree"/items/*/home/.config/cinnamon/spices/panel-launchers@cinnamon.org/*.json; do
            [ -f "$f" ] && json_list "$f" launcherList | sed "s/\$/\t$(item_of "$f")/"
        done
        for f in "$tree"/items/*/home/.config/mimeapps.list; do
            [ -f "$f" ] && awk -F= -v i="$(item_of "$f")" '/^\[/ { on = ($0 == "[Default Applications]"); next }
                on && NF == 2 { n = split($2, a, ";"); for (k = 1; k <= n; k++) if (a[k] != "") print a[k] "\t" i }' "$f"
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
            fcitx)  command -v fcitx >/dev/null 2>&1       || printf 'input\tfcitx\t%s\n' "$(item_of "$f")" ;;
            fcitx5) command -v fcitx5 >/dev/null 2>&1      || printf 'input\tfcitx5\t%s\n' "$(item_of "$f")" ;;
            ibus)   command -v ibus-daemon >/dev/null 2>&1 || printf 'input\tibus\t%s\n' "$(item_of "$f")" ;;
        esac
    done

    # --- Languages ---
    local have_locales="$CC_TMP/refs-locales.txt"
    locale -a 2>/dev/null | norm_locale | sort -u > "$have_locales"
    {
        for f in "$tree"/items/*/language.txt; do
            [ -f "$f" ] && cut -d= -f2 "$f" | sed "s/\$/\t$(item_of "$f")/"
        done
        for f in "$tree"/items/*/root/etc/default/locale; do
            [ -f "$f" ] && cut -d= -f2 "$f" | tr -d '"' | sed "s/\$/\t$(item_of "$f")/"
        done
        true
    } | while IFS=$'\t' read -r v x; do
        [ -n "$v" ] && [ "$v" != "C" ] && [ "$v" != "POSIX" ] || continue
        grep -qx "$(printf '%s\n' "$v" | norm_locale)" "$have_locales" || printf 'locale\t%s\t%s\n' "$v" "$x"
    done | sort -u -t$'\t' -k2,2

    # --- Sound theme ---
    v="$(setting /org/gnome/desktop/sound/theme-name)"
    if [ -n "$v" ] && [ ! -d "/usr/share/sounds/$v" ] && [ ! -d "$HOME/.local/share/sounds/$v" ]; then
        printf 'sound\t%s\t%s\n' "$v" "$(setting_item /org/gnome/desktop/sound/theme-name)"
    fi

    # --- Software ---
    for f in "$tree"/items/*/software.txt; do
        [ -f "$f" ] || continue
        where="$(item_of "$f")"
        local installed="$CC_TMP/refs-dpkg.txt" flatpaks="$CC_TMP/refs-flatpak.txt"
        dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null | awk '$NF == "installed" { print $1 }' | sort -u > "$installed"
        { flatpak list --app --columns=application 2>/dev/null || true; } | sort -u > "$flatpaks"
        { software_section "$f" apps; software_section "$f" language-support; } | while IFS= read -r x; do
            grep -qx "$x" "$installed" || printf 'apt\t%s\t%s\n' "$x" "$where"
        done
        software_section "$f" flatpak | while IFS=$'\t' read -r x v; do
            x="${x%% *}"; [ -n "$x" ] || continue
            grep -qx "$x" "$flatpaks" || printf 'flatpak\t%s\t%s\t%s\n' "$x" "$where" "${v:-flathub}"
        done
        software_section "$f" local-programs | while IFS= read -r x; do
            [ -e "$x" ] || printf 'program\t%s\t%s\n' "$x" "$where"
        done
        software_section "$f" sources | while IFS=$'\t' read -r x v; do
            [ -e "/etc/apt/sources.list.d/$x" ] || printf 'source\t%s\t%s\n' "$x" "$where"
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

# show_missing REFS TREE -> what the can uses that is not installed here
#   (themes, fonts, apps ...), with commands to install the software.
#   The heading always starts the same way, so the eye finds it:
#     INFO  Software, themes and fonts the can uses:
#           └ All installed on this computer
#   or, when something is missing, a warning with a table:
#     WARN  Software, themes and fonts the can uses, not installed here:
#             TYPE      NAME          USED BY ITEM
#           └ apt       code          software
#   (On the normal output, since it is part of a report.)
show_missing() {
    local refs="$1" tree="$2" kind name where remote apt="" flat="" l shown
    local heading="Software, themes and fonts the can uses"
    say ""
    if [ ! -s "$refs" ]; then
        info "$heading:" "${SUB}All installed on this computer"
        return 0
    fi
    msg_lines "$B_WARN" "$heading, not installed here:"
    table_head 9 "TYPE" 36 "NAME" 0 "USED BY ITEM"
    while IFS=$'\t' read -r kind name where remote; do
        # The names come from the can. In the table they are shown as
        # plain text (to_visible); in the commands to copy each one is
        # also kept as one word (shell_word), so a "name" such as
        # "x; rm -rf ~" can only fail as a package name, never run.
        to_visible shown "$name"
        printf '%s%-9s %-36s %s%s\n' "$ROW" "$kind" "$shown" "$(item_dot "$where")" "$where"
        case "$kind" in
            apt)     apt="$apt $(shell_word "$name")" ;;
            flatpak) flat="${flat}flatpak install $(shell_word "${remote:-flathub}") $(shell_word "$name")"$'\n' ;;
        esac
    done < "$refs"
    if [ -n "$apt$flat" ]; then
        say ""
        if grep -q '^source' "$refs"; then
            say "Add the missing software sources first (the \"source\" rows above)."
        fi
        say "To install the missing software, check the list above, then run:"
        [ -z "$apt" ] || say "\$ sudo apt install$apt"
        [ -z "$flat" ] || while IFS= read -r l; do [ -z "$l" ] || say "\$ $l"; done <<< "$flat"
    fi
}
