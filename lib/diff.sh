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
#      Optional items and your own items come in a separate "Extra" part,
#      and what this computer lacks comes last ("Missing on this computer").

# shellcheck source=lib/collect.sh
source "$CC_ROOT/lib/collect.sh"
# shellcheck source=lib/list.sh
source "$CC_ROOT/lib/list.sh"

WALLPAPER_COPY_DIR=".local/share/backgrounds/cinnamon-can"

cmd_diff() {
    [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: cinnamon-can diff CAN [CAN2]"
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
    local plus_can minus_can="" minus_label notes n
    plus_can="$(resolve_can "${2:-$1}")" || exit 1
    [ $# -eq 1 ] || { minus_can="$(resolve_can "$1")" || exit 1; }

    CMP_MINUS="$CC_TMP/minus" CMP_PLUS="$CC_TMP/plus"
    CMP_RESULT="$CC_TMP/result.txt" CMP_REPORT="$CC_TMP/report.txt"

    # The "+" side is always a can; its own catalog decides what is what.
    open_can "$plus_can" "$CC_TMP/can-plus"
    CMP_PLUS_ID="${MAN[can.id]}"
    local plus_home="${MAN[can.home]}" plus_label
    plus_label="can ${MAN[can.id]}${MAN[can.label]:+ \"${MAN[can.label]}\"}"
    notes="$(version_notes)"
    load_items "$CC_TMP/can-plus/catalog/builtin" "$CC_TMP/can-plus/catalog/user"

    if [ -z "$minus_can" ]; then
        # This computer against the can: only items switched on (in your
        # config, or by the can's defaults) and present in the can.
        CMP_ITEMS=()
        for n in $(tree_items "$CC_TMP/can-plus"); do item_on "$n" && CMP_ITEMS+=("$n"); done
        [ "${#CMP_ITEMS[@]}" -gt 0 ] || die "nothing to compare: every item of this can is switched off"
        info "reading this computer ..."
        collect_tree "$CMP_MINUS" "${CMP_ITEMS[@]}"
        prepare_view "$CC_TMP/can-plus" "$plus_home" "$CMP_PLUS" 1 "${CMP_ITEMS[@]}"
        minus_label="this computer"
    else
        # Two cans: every item either can has, unless switched off.
        open_can "$minus_can" "$CC_TMP/can-minus"
        local minus_home="${MAN[can.home]}"
        minus_label="can ${MAN[can.id]}${MAN[can.label]:+ \"${MAN[can.label]}\"}"
        notes=""
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
        say "Comparing ${C_RED}- $minus_label${C_RESET} with ${C_GREEN}+ $plus_label${C_RESET}"
        if [ -n "$notes" ]; then
            printf '%s\n' "$notes" | sed "s/^/${C_YELLOW}Warning:${C_RESET} /"
        fi
        render_diff
        title "== Missing on this computer"
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
#   including the language and the time zone.
flat_settings() {
    local view="$1" n d; shift
    for n in "$@"; do
        d="$view/items/$n"
        [ -f "$d/dconf.ini" ] && ini_flat "$d/dconf.ini" "$n"
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
#   "ignore" fields of the items (see lib/items.sh).
write_ignore_rules() {
    local n p
    for n in "$@"; do
        while IFS= read -r p; do
            printf '%s\thome/%s\t%s\n' "$n" "$(printf '%s' "${p%%:*}" | sed 's|^~/||')" "${p#*:}"
        done < <(split_words "${ITEM_IGNORE[$n]:-}")
    done > "$CC_TMP/ignore-rules.txt"
}

# ignore_rules_for ITEM REL -> the line beginnings to ignore in that file;
#   fails when there are none.
ignore_rules_for() {
    awk -F'\t' -v i="$1" -v r="$2" '$1 == i && $2 == r { print $3; found = 1 } END { exit !found }' \
        "$CC_TMP/ignore-rules.txt" 2>/dev/null
}

# without_ignored FILE BEGINNINGS -> FILE without the lines that start with
#   one of the BEGINNINGS (one per line in that file).
without_ignored() {
    awk 'FNR == NR { b[++n] = $0; next }
         { for (i = 1; i <= n; i++) if (index($0, b[i]) == 1) next; print }' "$2" "$1"
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
    for n in "${main[@]+"${main[@]}"}"; do render_item "$n"; done
    if [ "${#extra[@]}" -gt 0 ]; then
        say ""; say "${C_BOLD}== Extra (optional and your own items) ==${C_RESET}"
        for n in "${extra[@]}"; do render_item "$n"; done
    fi
}

# render_item ITEM -> the differences of one item: settings, then files.
render_item() {
    local n="$1" result="$CC_TMP/item-result.txt" it kind path state va vb a b label tag
    # Settings first, then files, the crontab, and system files last.
    awk -F'\t' -v i="$n" '$1 == i {
        o = ($2 == "setting") ? 1 : ($2 == "file") ? 2 : ($2 == "crontab") ? 3 : 4
        print o "\t" $0 }' "$CMP_RESULT" | sort -t$'\t' -k1,1n -k4,4 | cut -f2- > "$result"
    title "== $n"
    while IFS=$'\t' read -r it kind path state va vb; do
        tag=""
        [ "$kind" = "system" ] || [ "$path" = "(time zone)" ] && tag="  ${C_YELLOW}[sudo]${C_RESET}"
        if [ "$kind" = "setting" ]; then
            say "${C_BOLD}--- $path${C_RESET}$tag"
            say "${C_RED}-$va${C_RESET}"
            say "${C_GREEN}+$vb${C_RESET}"
            continue
        fi
        label="$(show_path "$kind" "$path")"
        a="$CMP_MINUS/items/$n/$path"; b="$CMP_PLUS/items/$n/$path"
        case "$state" in
            added)   say "${C_BOLD}--- $label${C_RESET}$tag  ${C_GREEN}(new file)${C_RESET}" ;;
            removed) say "${C_BOLD}--- $label${C_RESET}$tag  ${C_RED}(deleted)${C_RESET}" ;;
            changed)
                say "${C_BOLD}--- $label${C_RESET}$tag"
                if [ -L "$a" ] || [ -L "$b" ]; then
                    say "${C_RED}-link to $(readlink "$a" 2>/dev/null || echo '(not a link)')${C_RESET}"
                    say "${C_GREEN}+link to $(readlink "$b" 2>/dev/null || echo '(not a link)')${C_RESET}"
                elif is_text "$a" && is_text "$b"; then
                    if ignore_rules_for "$n" "$path" > "$CC_TMP/ignore-now.txt"; then
                        { diff -u <(without_ignored "$a" "$CC_TMP/ignore-now.txt") \
                                  <(without_ignored "$b" "$CC_TMP/ignore-now.txt") || true; } | tail -n +3 | color_diff
                    else
                        { diff -u "$a" "$b" || true; } | tail -n +3 | color_diff
                    fi
                else
                    say "  (binary file differs)"
                fi ;;
        esac
    done < "$result"
}

# color_diff -> colours the body of a "diff -u".
color_diff() {
    if [ -n "$C_RESET" ]; then
        sed -e "s/^-.*/${C_RED}&${C_RESET}/" -e "s/^+.*/${C_GREEN}&${C_RESET}/" -e "s/^@@.*/${C_DIM}&${C_RESET}/"
    else
        cat
    fi
}

summary_line() {
    local s f y
    # The time zone needs sudo, so it counts as a system change here --
    # the same way the [sudo] marks and the "open" messages count it.
    s="$(awk -F'\t' '$2 == "setting" && $3 != "(time zone)"' "$CMP_RESULT" | wc -l)"
    f="$(awk -F'\t' '$2 == "file" || $2 == "crontab"' "$CMP_RESULT" | wc -l)"
    y="$(awk -F'\t' '$2 == "system" || $3 == "(time zone)"' "$CMP_RESULT" | wc -l)"
    say "${C_BOLD}Summary:${C_RESET} $s setting(s), $f file(s), $y system change(s) differ; $(wc -l < "$CC_TMP/refs.txt") thing(s) missing"
}
