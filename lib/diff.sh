# lib/diff.sh -- the "diff" command, and the comparison "open" shows.
#
#   cinnamon-can diff CAN          this computer (-) against the can (+)
#   cinnamon-can diff CAN1 CAN2    CAN1 (-) against CAN2 (+)
#
# How it works:
#   1. Both sides become a "view": a folder with items/ITEM/... in the
#      layout of a can. For a can, the view is what "open" would write:
#      the old home folder is replaced by yours, and a wallpaper image
#      this computer lacks is placed in ~/.local/share/backgrounds/cinnamon-can/.
#      For this computer, the view is read with the same code as "seal".
#   2. The two views are lined up: every setting and every file that
#      differs becomes one line in a result list.
#   3. The result is shown like "git diff": per item, settings first,
#      then files. Settings a side does not have are "(default)".
#      Optional items and your own items come last, marked as such, and
#      after them what the can uses that this computer has not installed.

# shellcheck source=lib/collect.sh
source "$CC_ROOT/lib/collect.sh"
# shellcheck source=lib/list.sh
source "$CC_ROOT/lib/list.sh"

WALLPAPER_COPY_DIR=".local/share/backgrounds/cinnamon-can"

cmd_diff() {
    [ $# -ge 1 ] && [ $# -le 2 ] || die "Usage: cinnamon-can diff CAN [CAN2]"
    make_tmpdir
    build_comparison "$@"
    show_paged "$CMP_REPORT"
    [ "$CMP_TOTAL" -eq 0 ]
}

# Results of build_comparison, used by "diff" and "open":
CMP_MINUS="" CMP_PLUS="" CMP_RESULT="" CMP_REPORT="" CMP_TOTAL=0 CMP_SYSTEM=0
CMP_PLUS_ID=""
CMP_ITEMS=()

# build_comparison CAN [CAN2]
build_comparison() {
    local plus_can minus_can="" minus_label notes n notes_title="Differs from this computer:"
    plus_can="$(resolve_can "${2:-$1}")" || exit 1
    [ $# -eq 1 ] || { minus_can="$(resolve_can "$1")" || exit 1; }

    CMP_MINUS="$CC_TMP/minus" CMP_PLUS="$CC_TMP/plus"
    CMP_RESULT="$CC_TMP/result.txt" CMP_REPORT="$CC_TMP/report.txt"

    # The "+" side is always a can; its own catalog decides what is what.
    open_can "$plus_can" "$CC_TMP/can-plus"
    CMP_PLUS_ID="${MAN[can.id]}"
    local plus_home="${MAN[can.home]}" plus_label
    plus_label="Can $(show_id "${MAN[can.id]}")${MAN[can.label]:+ (label: ${MAN[can.label]})}"
    notes="$(version_notes)"
    # Kept for a second can, whose manifest replaces MAN below.
    local p_id="${MAN[can.id]}" p_rel="${MAN[can.mint_release]:-?}" p_ed="${MAN[can.mint_edition]:-?}"
    local p_cin="${MAN[can.cinnamon_version]:-?}" p_arch="${MAN[can.arch]:-?}"
    keep_own_ignore     # before the can's items replace this computer's
    load_items "$CC_TMP/can-plus/catalog/builtin" "$CC_TMP/can-plus/catalog/user"

    if [ -z "$minus_can" ]; then
        # This computer against the can: only items switched on (in your
        # config, or by the can's defaults) and present in the can.
        CMP_ITEMS=()
        for n in $(tree_items "$CC_TMP/can-plus"); do item_on "$n" && CMP_ITEMS+=("$n"); done
        [ "${#CMP_ITEMS[@]}" -gt 0 ] || die "Nothing to compare: every item of this can is switched off"
        info "Reading this computer's settings ..."
        collect_tree "$CMP_MINUS" "${CMP_ITEMS[@]}"
        prepare_view "$CC_TMP/can-plus" "$plus_home" "$CMP_PLUS" 1 "${CMP_ITEMS[@]}"
        minus_label="This computer"
    else
        # Two cans: every item either can has, unless switched off.
        open_can "$minus_can" "$CC_TMP/can-minus"
        local minus_home="${MAN[can.home]}"
        minus_label="Can $(show_id "${MAN[can.id]}")${MAN[can.label]:+ (label: ${MAN[can.label]})}"
        notes="$(versions_between "$p_id" "$p_rel" "$p_ed" "$p_cin" "$p_arch")"
        notes_title="The two cans were made on different versions:"
        CMP_ITEMS=()
        for n in $( { ls "$CC_TMP/can-minus/items" "$CC_TMP/can-plus/items" 2>/dev/null || true; } | sort -u); do
            [ "${CONF_ITEMS[$n]:-yes}" = "no" ] || CMP_ITEMS+=("$n")
        done
        prepare_view "$CC_TMP/can-minus" "$minus_home" "$CMP_MINUS" 0 "${CMP_ITEMS[@]}"
        prepare_view "$CC_TMP/can-plus" "$plus_home" "$CMP_PLUS" 0 "${CMP_ITEMS[@]}"
    fi

    compare_views "$CMP_MINUS" "$CMP_PLUS" "$CMP_RESULT" "${CMP_ITEMS[@]}"
    CMP_TOTAL="$(wc -l < "$CMP_RESULT")"
    CMP_SYSTEM="$(awk -F'\t' '$2 == "system" || $3 == "(time zone)"' "$CMP_RESULT" | wc -l)"

    {
        # The two sides, with the same "-" and "+" as the lines below.
        info "Comparing:" "${C_RED}(-)${C_RESET} $minus_label" "${C_GREEN}(+)${C_RESET} $plus_label"
        show_version_notes "$notes" "$notes_title"
        render_diff
        check_refs "$CMP_PLUS" > "$CC_TMP/refs.txt"
        show_missing "$CC_TMP/refs.txt" "$CMP_PLUS"
        say ""
        summary_line
    } > "$CMP_REPORT"
}


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------

# prepare_view SRC SRC_HOME OUT FIX_WALLPAPER ITEM...
prepare_view() {
    local src="$1" src_home="$2" out="$3" fix="$4" n f t; shift 4
    rm -rf "$out"; mkdir -p "$out/items"
    for n in "$@"; do
        [ -d "$src/items/$n" ] && cp -a "$src/items/$n" "$out/items/$n"
    done

    # The can was made under another home folder: write yours instead,
    # in settings, text files and symlinks.
    if [ -n "$src_home" ] && [ "$src_home" != "$HOME" ]; then
        while IFS= read -r f; do
            if [ -L "$f" ]; then
                t="$(readlink "$f")"
                [[ "$t" == *"$src_home"* ]] && ln -sfn "${t//"$src_home"/$HOME}" "$f"
            elif is_text "$f"; then
                replace_text "$f" "$src_home" "$HOME"
            fi
        done < <(find "$out/items" \( -type f -o -type l \) ! -path '*/wallpaper/*' 2>/dev/null || true)
    fi

    [ "$fix" != "1" ] || fix_wallpaper "$out"
    return 0
}

# fix_wallpaper VIEW -> if the wallpaper image is not on this computer, put
#   the copy from the can in ~/.local/share/backgrounds/cinnamon-can/ and
#   point the wallpaper setting there.
fix_wallpaper() {
    local view="$1" wt d orig name ini
    for wt in "$view"/items/*/wallpaper.txt; do
        [ -f "$wt" ] || continue
        d="$(dirname "$wt")"; orig="$(cat "$wt")"; name="$(basename "$orig")"
        [ ! -f "$orig" ] || continue                                   # it is here
        [ -f "$d/wallpaper/$name" ] || continue
        [ "$orig" != "$HOME/$WALLPAPER_COPY_DIR/$name" ] || continue   # comes as a file
        mkdir -p "$d/home/$WALLPAPER_COPY_DIR"
        cp -p "$d/wallpaper/$name" "$d/home/$WALLPAPER_COPY_DIR/$name"
        for ini in "$view"/items/*/dconf.ini; do
            [ -f "$ini" ] && point_wallpaper "$ini" "$HOME/$WALLPAPER_COPY_DIR"
        done
    done
    return 0
}

# point_wallpaper INI FOLDER -> picture-uri points into FOLDER. The file
#   name is kept exactly as written in the old address.
point_wallpaper() {
    local dir
    dir="$(uri_path "$2")"
    awk -v dir="$dir" '
        /^\[/ { sec = $0 }
        sec == "[org/cinnamon/desktop/background]" && /^picture-uri=/ {
            name = $0; sub(/^.*\//, "", name)
            print "picture-uri='"'"'file://" dir "/" name; next }
        { print }' "$1" > "$1.cc-tmp"
    mv "$1.cc-tmp" "$1"
}

# uri_path PATH -> PATH written for a file:// address (space -> %20 ...).
uri_path() {
    LC_ALL=C awk -v s="$1" 'BEGIN {
        for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            out = out ((c ~ /[A-Za-z0-9\/._~-]/) ? c : sprintf("%%%02X", ord[c]))
        }
        print out }'
}


# ---------------------------------------------------------------------------
# Comparing two views
# ---------------------------------------------------------------------------

# flat_settings VIEW ITEM... -> item<TAB>path<TAB>value for every setting,
#   including the language and the time zone, except the settings the
#   item ignores (they are still restored, but never count as a change).
flat_settings() {
    local view="$1" n d; shift
    for n in "$@"; do
        d="$view/items/$n"
        [ -f "$d/dconf.ini" ] && flat_without_ignored "$d/dconf.ini" "$n"
        [ -f "$d/language.txt" ] && awk -F= -v n="$n" 'NF { print n "\t(language) " $1 "\t" substr($0, index($0, "=") + 1) }' "$d/language.txt"
        [ -f "$d/timezone.txt" ] && printf '%s\t(time zone)\t%s\n' "$n" "$(cat "$d/timezone.txt")"
    done
    return 0
}

# view_files VIEW ITEM... -> item<TAB>home/...|root/...|crontab.txt
view_files() {
    local view="$1" n; shift
    for n in "$@"; do
        [ -d "$view/items/$n" ] || continue
        ( cd "$view/items/$n" && { find home root \( -type f -o -type l \) 2>/dev/null || true
                                   [ ! -f crontab.txt ] || echo crontab.txt; } ) | sed "s|^|$n\t|"
    done
    return 0
}

# compare_views MINUS PLUS RESULT ITEM...
#   RESULT lines: item<TAB>kind<TAB>path<TAB>state<TAB>minus<TAB>plus
#     kind        setting | file | system | crontab
#     state       changed | added (only +) | removed (only -)
#     minus/plus  the two values of a setting; "(default)" stands for a
#                 side that does not have it (empty for files)
compare_views() {
    local minus="$1" plus="$2" result="$3" n kind rel a b; shift 3
    flat_settings "$minus" "$@" > "$CC_TMP/flat-minus.txt"
    flat_settings "$plus" "$@" > "$CC_TMP/flat-plus.txt"
    awk -F'\t' -v OFS='\t' -v fa="$CC_TMP/flat-minus.txt" '
        FILENAME == fa { A[$1 SUBSEP $2] = $3; K[$1 SUBSEP $2] = 1; next }
                       { B[$1 SUBSEP $2] = $3; K[$1 SUBSEP $2] = 1 }
        END {
            for (k in K) {
                split(k, p, SUBSEP); ina = (k in A); inb = (k in B)
                if (ina && inb && A[k] == B[k]) continue
                st = (ina && inb) ? "changed" : (ina ? "removed" : "added")
                # A side without the setting (or with an empty value) is
                # written as "(default)". It must not stay empty: when the
                # line is read back, two tab characters next to each other
                # count as ONE separator, and the columns would shift.
                va = (ina ? A[k] : ""); if (va == "") va = "(default)"
                vb = (inb ? B[k] : ""); if (vb == "") vb = "(default)"
                print p[1], "setting", p[2], st, va, vb
            }
        }' "$CC_TMP/flat-minus.txt" "$CC_TMP/flat-plus.txt" > "$result"

    write_ignore_rules "$@"
    { view_files "$minus" "$@"; view_files "$plus" "$@"; } | sort -u | while IFS=$'\t' read -r n rel; do
        case "$rel" in root/*) kind=system ;; crontab.txt) kind=crontab ;; *) kind=file ;; esac
        a="$minus/items/$n/$rel"; b="$plus/items/$n/$rel"
        if { [ -e "$a" ] || [ -L "$a" ]; } && { [ -e "$b" ] || [ -L "$b" ]; }; then
            same_file "$a" "$b" "$n" "$rel" || printf '%s\t%s\t%s\tchanged\t\t\n' "$n" "$kind" "$rel"
        elif [ -e "$a" ] || [ -L "$a" ]; then
            # System files are never deleted.
            [ "$kind" = "system" ] || printf '%s\t%s\t%s\tremoved\t\t\n' "$n" "$kind" "$rel"
        else
            printf '%s\t%s\t%s\tadded\t\t\n' "$n" "$kind" "$rel"
        fi
    done >> "$result"
    return 0
}

# same_file A B [ITEM REL] -> success if both are the same symlink, or the
#   same bytes -- not counting the lines the item says to ignore.
same_file() {
    if [ -L "$1" ] || [ -L "$2" ]; then
        [ -L "$1" ] && [ -L "$2" ] && [ "$(readlink "$1")" = "$(readlink "$2")" ]
    elif [ -n "${3:-}" ] && ignore_rules_for "$3" "$4" > "$CC_TMP/ignore-now.txt"; then
        cmp -s <(without_ignored "$1" "$CC_TMP/ignore-now.txt") <(without_ignored "$2" "$CC_TMP/ignore-now.txt")
    else
        cmp -s "$1" "$2"
    fi
}

# write_ignore_rules ITEM... -> item<TAB>home/path<TAB>beginning, from the
#   file lines in the "ignore" fields of the items (see lib/items.sh).
write_ignore_rules() {
    local n p file
    for n in "$@"; do
        while IFS= read -r p; do
            [[ "$p" == "~/"* ]] || continue        # settings: see flat_settings
            file="${p%%:*}"
            printf '%s\thome/%s\t%s\n' "$n" "${file#\~/}" "${p#*:}"
        done < <(ignore_words "$n")
    done > "$CC_TMP/ignore-rules.txt"
}

# ignore_rules_for ITEM REL -> the line beginnings to ignore in that file;
#   fails when there are none.
ignore_rules_for() {
    awk -F'\t' -v i="$1" -v r="$2" '$1 == i && $2 == r { print $3; found = 1 } END { exit !found }' \
        "$CC_TMP/ignore-rules.txt" 2>/dev/null
}

# without_ignored FILE BEGINNINGS [MAP] -> FILE without the lines that start
#   with one of the BEGINNINGS (one per line in that file). With MAP, the
#   real line number of every line kept is written there, one per line.
without_ignored() {
    awk -v map="${3:-}" 'FNR == NR { b[++n] = $0; next }
         { for (i = 1; i <= n; i++) if (index($0, b[i]) == 1) next
           if (map != "") print FNR > map
           print }
         END { if (map != "") close(map) }   # written before diff reads the end' "$2" "$1"
}


# ---------------------------------------------------------------------------
# Showing the result
# ---------------------------------------------------------------------------

# show_path KIND REL -> how a path is shown: ~/..., /etc/..., crontab
show_path() {
    case "$2" in
        home/*)      printf '~/%s' "${2#home/}" ;;
        root/*)      printf '/%s' "${2#root/}" ;;
        crontab.txt) printf 'crontab' ;;
        *)           printf '%s' "$2" ;;
    esac
}

# The report shows each item as a heading, and under it one entry per
# setting or file that differs (a file with a yellow dot):
#
#          appearance
#          └ /org/cinnamon/desktop/interface/font-name
#        -     'Waree 11'
#        +     'Ubuntu 11'
#          └ • ~/.config/cinnamon/spices/calendar@cinnamon.org/13.json  (+1 | -1)
#            10  "tooltip": "Check this to display events in the calendar.",
#        -   11  "value": true
#        +   11  "value": false
#      NEW └ • ~/.config/cinnamon/spices/calendar@cinnamon.org/99.json  (+3 | -0)
#
# The "-" side is this computer (or the first can), the "+" side the can.
# Lines of a file carry their line number in grey; "⋯" marks lines left
# out between two changed parts. What needs sudo is marked SUDO REQUIRED.

render_diff() {
    local n
    local -a main=() extra=()
    for n in "${CMP_ITEMS[@]}"; do
        grep -q "^$n	" "$CMP_RESULT" || continue          # nothing differs
        if is_main_item "$n"; then main+=("$n"); else extra+=("$n"); fi
    done
    if [ "${#main[@]}" -eq 0 ] && [ "${#extra[@]}" -eq 0 ]; then
        say ""; say "No differences."; return 0
    fi
    # The usual items first, then the optional ones and your own, each
    # with a grey note after its name.
    for n in "${main[@]+"${main[@]}"}" "${extra[@]+"${extra[@]}"}"; do render_item "$n"; done
}

# item_note ITEM -> " (optional item)" or " (your own item)" in grey;
#   nothing for an item that is on by default.
item_note() {
    if [ "${ITEM_SRC[$1]:-}" = "user" ]; then printf ' %s(your own item)%s' "$C_GREY" "$C_RESET"
    elif ! is_main_item "$1"; then printf ' %s(optional item)%s' "$C_GREY" "$C_RESET"; fi
}

# render_item ITEM -> the differences of one item: settings, then files.
render_item() {
    local n="$1" result="$CC_TMP/item-result.txt" body="$CC_TMP/item-body.txt"
    local it kind path state va vb a b label tag ma mb p m
    # Settings first, then files, the crontab, and system files last.
    awk -F'\t' -v i="$n" '$1 == i {
        o = ($2 == "setting") ? 1 : ($2 == "file") ? 2 : ($2 == "crontab") ? 3 : 4
        print o "\t" $0 }' "$CMP_RESULT" | sort -t$'\t' -k1,1n -k4,4 | cut -f2- > "$result"
    say ""
    say "${C_BOLD}$n${C_RESET}$(item_note "$n")"
    while IFS=$'\t' read -r it kind path state va vb; do
        tag=""
        [ "$kind" != "system" ] && [ "$path" != "(time zone)" ] || tag=" $B_SUDO"
        if [ "$kind" = "setting" ]; then
            say "${SUB}$path$tag"
            change_line - "$(value_word "$va")"
            change_line + "$(value_word "$vb")"
            continue
        fi
        label="$(file_dot "$(show_path "$kind" "$path")")$tag"
        a="$CMP_MINUS/items/$n/$path"; b="$CMP_PLUS/items/$n/$path"
        case "$state" in
            added)   printf '%s%s%s%s\n' "$B_NEW" "$SUB" "$label" "$(line_counts 0 "$b")" ;;
            removed) printf '%s%s%s%s\n' "$B_DEL" "$SUB" "$label" "$(line_counts "$a" 0)" ;;
            changed)
                if [ -L "$a" ] || [ -L "$b" ]; then
                    say "${SUB}$label"
                    change_line - "link to $(readlink "$a" 2>/dev/null || echo '(not a link)')"
                    change_line + "link to $(readlink "$b" 2>/dev/null || echo '(not a link)')"
                elif is_text "$a" && is_text "$b"; then
                    ma="" mb=""
                    if ignore_rules_for "$n" "$path" > "$CC_TMP/ignore-now.txt"; then
                        # Ignored lines are left out, but every line keeps
                        # its real number (ma/mb: shown line -> real line).
                        ma="$CC_TMP/map-a.txt" mb="$CC_TMP/map-b.txt"
                        : > "$ma"; : > "$mb"
                        { diff -u <(without_ignored "$a" "$CC_TMP/ignore-now.txt" "$ma") \
                                  <(without_ignored "$b" "$CC_TMP/ignore-now.txt" "$mb") || true; } > "$body"
                    else
                        { diff -u "$a" "$b" || true; } > "$body"
                    fi
                    p="$(awk 'NR > 2 && /^\+/' "$body" | wc -l)"
                    m="$(awk 'NR > 2 && /^-/' "$body" | wc -l)"
                    say "${SUB}$label  $(line_counts_text "$p" "$m")"
                    tail -n +3 "$body" | diff_body "$ma" "$mb"
                else
                    say "${SUB}$label"
                    say "  ${C_GREY}(binary file differs)${C_RESET}"
                fi ;;
        esac
    done < "$result"
}

# change_line -|+ TEXT -> one changed value, with its badge in the left
#   column (no line number: settings have none).
change_line() {
    local badge="$B_MINUS" colour="$C_RED"
    [ "$1" = "-" ] || { badge="$B_PLUS"; colour="$C_GREEN"; }
    printf '     %s   %s%s%s\n' "$badge" "$colour" "$2" "$C_RESET"
}

# line_counts OLD NEW -> "  (+12 | -0)" for a new text file of 12 lines (each
#   side is a file, or 0 when that side has none); nothing for a binary
#   file, and nothing for a link: it has no lines of its own, and what it
#   points to may not exist on this computer.
line_counts() {
    local p=0 m=0
    if [ "$1" != 0 ]; then [ ! -L "$1" ] && is_text "$1" || return 0; m="$(wc -l < "$1")"; fi
    if [ "$2" != 0 ]; then [ ! -L "$2" ] && is_text "$2" || return 0; p="$(wc -l < "$2")"; fi
    printf '  %s' "$(line_counts_text "$p" "$m")"
}

# diff_body [MAP_A MAP_B] -> the body of a "diff -u" (read from the input,
#   without its first 2 lines): every changed line with a "-"/"+" badge in
#   the left column; in the right column the line number in grey, then
#   the text. The MAPs turn
#   a shown line number into the real one (when lines were left out).
diff_body() {
    awk -v ma="${1:-}" -v mb="${2:-}" -v grey="$C_GREY" -v red="$C_RED" -v green="$C_GREEN" \
        -v off="$C_RESET" -v bm="$B_MINUS" -v bp="$B_PLUS" '
        BEGIN { if (ma != "") while ((getline l < ma) > 0) A[++na] = l
                if (mb != "") while ((getline l < mb) > 0) B[++nb] = l }
        function real_a(n) { return (ma != "" && n in A) ? A[n] : n }
        function real_b(n) { return (mb != "" && n in B) ? B[n] : n }
        /^@@/ { o = substr($2, 2) + 0; n = substr($3, 2) + 0
                if (hunks++) printf "            %s⋯%s\n", grey, off
                next }
        /^\\/ { printf "               %s%s%s\n", grey, substr($0, 3), off; next }
        { c = substr($0, 1, 1); t = substr($0, 2) }
        c == "-" { printf "     %s %s%4s%s  %s%s%s\n", bm, grey, real_a(o), off, red, t, off; o++; next }
        c == "+" { printf "     %s %s%4s%s  %s%s%s\n", bp, grey, real_b(n), off, green, t, off; n++; next }
                 { printf "         %s%4s%s  %s\n", grey, real_b(n), off, t; o++; n++ }'
}

# summary_line -> what differs, one row per kind, with a coloured dot:
#   green = nothing, yellow = differs, orange = needs sudo, red = missing.
summary_line() {
    local s f y m
    # The time zone needs sudo, so it counts as a system change here --
    # the same way its SUDO REQUIRED mark and the "open" messages do.
    s="$(awk -F'\t' '$2 == "setting" && $3 != "(time zone)"' "$CMP_RESULT" | wc -l)"
    f="$(awk -F'\t' '$2 == "file" || $2 == "crontab"' "$CMP_RESULT" | wc -l)"
    y="$(awk -F'\t' '$2 == "system" || $3 == "(time zone)"' "$CMP_RESULT" | wc -l)"
    m="$(wc -l < "$CC_TMP/refs.txt")"
    info "Summary of the comparison above:" \
        "${SUB}$(status_dot "$s" "$C_YELLOW") $s setting(s) differ" \
        "${SUB}$(status_dot "$f" "$C_YELLOW") $f file(s) differ" \
        "${SUB}$(status_dot "$y" "$C_ORANGE") $y system change(s) differ (only with sudo)" \
        "${SUB}$(status_dot "$m" "$C_RED") $m thing(s) used by the can but not installed here (listed above)"
}

# status_dot COUNT COLOUR -> a green dot for 0, else a dot in COLOUR.
status_dot() {
    if [ "$1" -eq 0 ]; then printf '%s●%s' "$C_GREEN" "$C_RESET"; else printf '%s●%s' "$2" "$C_RESET"; fi
}
