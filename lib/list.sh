# lib/list.sh -- the "list" and "peek" commands, and reading cans.
#
#   list        every can in the backup folder, newest first
#   peek CAN    what is inside one can (only the can: it is not compared
#               with this computer; "diff CAN" does that)

# MAN holds the manifest of the can that was opened last:
#   MAN[can.id], MAN[can.label], MAN[can.home], MAN[items.keyboard] ...
declare -A MAN=()

# read_manifest FILE -> fills MAN. (Labels may contain any text, so this
#   reader does not treat "#" as a comment.)
read_manifest() {
    local section key value
    MAN=()
    while IFS=$'\t' read -r section key value; do
        MAN[$section.$key]="$value"
    done < <(awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        /^\[.*\]$/ { sec = substr($0, 2, length($0) - 2); next }
        /^[ \t]*(#|$)/ { next }
        { eq = index($0, "="); if (eq) print sec "\t" trim(substr($0, 1, eq - 1)) "\t" trim(substr($0, eq + 1)) }' "$1")
}

# manifest_complete -> success when the manifest has every field a can
#   always gets when it is made. A hand-made or damaged manifest would
#   otherwise stop the program with an unhelpful "unbound variable".
manifest_complete() {
    local k
    for k in id kind created hostname home mint_release mint_edition cinnamon_version arch; do
        [ -n "${MAN[can.$k]+set}" ] || return 1
    done
}

# open_can PATH DIR -> unpacks a can into DIR and reads its manifest.
open_can() {
    local can="$1" dir="$2"
    rm -rf "$dir"; mkdir -p "$dir"
    tar -C "$dir" -xzf "$can" 2>/dev/null || not_a_can "$can" damaged
    [ -f "$dir/manifest.txt" ] || not_a_can "$can" no-manifest
    read_manifest "$dir/manifest.txt"
    manifest_complete || not_a_can "$can" incomplete
}

# not_a_can PATH WHY -> stops with what is wrong with the can (WHY:
#   damaged, no-manifest or incomplete), the can on its own line under it.
not_a_can() {
    local why
    case "$2" in
        damaged)     why="cannot be unpacked; it is damaged or not a can" ;;
        no-manifest) why="has no manifest; it was not made by cinnamon-can" ;;
        *)           why="has an incomplete manifest; it was not made by cinnamon-can" ;;
    esac
    die "The specified can $why:" "${SUB}$(file_dot "$(to_tilde "$1")")"
}

# label_or_none TEXT -> TEXT, or a grey "(none)" when there is no label,
#   so it does not read like a label.
label_or_none() {
    if [ -n "$1" ]; then printf '%s' "$1"; else printf '%s(none)%s' "$C_GREY" "$C_RESET"; fi
}

# tree_items TREE -> the items stored in a tree, in catalog order.
tree_items() {
    local n
    for n in "${ITEM_NAMES[@]}"; do [ -d "$1/items/$n" ] && printf '%s\n' "$n"; done
    return 0
}

# can_header TEXT -> TEXT (e.g. "Sealing the can [K7Q2] ..."), then what
#   the opened can (MAN) is, one fact per line:
#     └ Label: before upgrade
#     └ When:  2026-11-13 14:30:00 +07:00
#     └ On:    mylaptop (Linux Mint 22.3, Cinnamon 6.6.9, x86_64)
#   A can without a label shows "Label: (none)", "(none)" in grey.
#   (The Mint edition is left out: it is always Cinnamon, since
#   cinnamon-can runs on nothing else.)
can_header() {
    local c="${MAN[can.created]}" more=()
    more+=("${SUB}Label: $(label_or_none "${MAN[can.label]:-}")")
    [ -z "${MAN[can.opened]:-}" ] \
        || more+=("${SUB}Kind:  autocan, saved just before opening can $(show_id "${MAN[can.opened]}")")
    more+=("${SUB}When:  ${c:0:10} ${c:11:8} ${c:19}"
           "${SUB}On:    ${MAN[can.hostname]} (Linux Mint ${MAN[can.mint_release]}, Cinnamon ${MAN[can.cinnamon_version]}, ${MAN[can.arch]})")
    info "$1" "${more[@]}"
}

# summarize_tree TEXT TREE -> TEXT, then one row per item: how many
#   settings and files it holds, and what else (EXTRAS: the wallpaper,
#   the language, the time zone, the software list, the crontab).
summarize_tree() {
    local tree="$2" n d settings files extra
    info "$1"
    table_head 16 "ITEM" -8 "SETTINGS" -6 "FILES" 0 "EXTRAS"
    while IFS= read -r n; do
        d="$tree/items/$n"
        settings=0; files=0; extra=""
        [ -f "$d/dconf.ini" ] && settings="$(ini_flat "$d/dconf.ini" | wc -l)"
        files="$( { find "$d/home" "$d/root" \( -type f -o -type l \) 2>/dev/null || true; } | wc -l)"
        [ -d "$d/wallpaper" ] && extra="$extra; wallpaper $(basename "$(cat "$d/wallpaper.txt" 2>/dev/null)")"
        [ -f "$d/language.txt" ] && extra="$extra; $(language_words "$d/language.txt")"
        [ -f "$d/timezone.txt" ] && extra="$extra; time zone $(cat "$d/timezone.txt")"
        [ -f "$d/crontab.txt" ] && extra="$extra; crontab"
        [ -f "$d/software.txt" ] && extra="$extra; $(software_counts "$d/software.txt")"
        printf '%s%s %8s %6s %s\n' "$ROW" "$(item_cell "$n" 16)" "$settings" "$files" "${extra#; }"
    done < <(tree_items "$tree")
}

# language_words FILE -> "language th_TH, formats en_US.UTF-8" from the
#   Language=... and FormatsLocale=... lines of language.txt.
language_words() {
    awk -F= '$1 == "Language" { $1 = "language" } $1 == "FormatsLocale" { $1 = "formats" }
             NF >= 2 { out = out (out == "" ? "" : ", ") $1 " " $2 } END { print out }' "$1"
}

# software_section FILE SECTION -> the lines of one [section] of software.txt
software_section() {
    awk -v s="[$2]" '/^\[/ { on = ($0 == s); next } on && NF' "$1"
}

# software_counts FILE -> "12 apps, 13 language packages, 1 flatpak"
software_counts() {
    printf '%s, %s, %s' \
        "$(counted "$(software_section "$1" apps | wc -l)" app)" \
        "$(counted "$(software_section "$1" language-support | wc -l)" "language package")" \
        "$(counted "$(software_section "$1" flatpak | wc -l)" flatpak)"
}

# counted N WORD -> "1 app", "2 apps"
counted() { if [ "$1" -eq 1 ]; then printf '1 %s' "$2"; else printf '%s %ss' "$1" "$2"; fi; }

# show_software TREE -> the full software list of a tree, one row per
#   kind. Long lists go on over more lines, under the first word.
show_software() {
    local f
    f="$( { find "$1/items" -name software.txt 2>/dev/null || true; } | head -n 1)"
    [ -n "$f" ] || return 0
    say ""
    info "List of software names stored in the can:" "${C_GREY}For reference only, never installed for you${C_RESET}"
    software_row "Apps"             "$(software_section "$f" apps)"
    software_row "Language support" "$(software_section "$f" language-support)"
    software_row "Flatpak"          "$(software_section "$f" flatpak | awk '{ print $1 }')"
    software_row "Local programs"   "$(software_section "$f" local-programs)"
    software_row "Sources"          "$(software_section "$f" sources | awk -F'\t' '{ print $1 }')"
}

# software_row NAME WORDS -> "└ Apps              code composer ..." with
#   the words wrapped to the width of the screen; "(none)" in grey when
#   there are no words, so it does not read like a name.
software_row() {
    printf '%s%-17s ' "$ROW" "$1"
    if [ -z "$2" ]; then printf '%s(none)%s\n' "$C_GREY" "$C_RESET"; return 0; fi
    printf '%s\n' "$2" | awk -v room="$(( $(screen_width) - 29 ))" -v pad="$MSG_INDENT                    " '
        { for (i = 1; i <= NF; i++) {
              if (used > 0 && used + 1 + length($i) > room) { printf "\n%s", pad; used = 0 }
              if (used > 0) { printf " "; used++ }
              printf "%s", $i
              used += length($i) } }
        END { printf "\n" }'
}


# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

cmd_list() {
    [ $# -eq 0 ] || die "Command \"list\" takes no arguments"
    make_tmpdir
    # The list grows with every seal and open: shown page by page (like
    # diff) when it is longer than the screen.
    list_report > "$CC_TMP/list.txt"
    show_paged "$CC_TMP/list.txt"
}

# list_report -> the whole list, as cmd_list shows it.
list_report() {
    local f line id skipped=() start more=()
    say ""
    if [ -z "$(all_cans)" ]; then
        info "Cans stored in $(to_tilde "$(backup_dir)"): none yet. Make one with:" "\$ cinnamon-can seal -L \"My first can\""
        return 0
    fi
    info "Cans stored in $(to_tilde "$(backup_dir)"):"
    can_table_head
    # Newest first: the first row gets a grey "Latest:" in the left
    # column (where the badges are), so the order is clear at a glance.
    start=" ${C_GREY}Latest:${C_RESET} $SUB"
    while IFS= read -r f; do
        if can_row "$start" "$f"; then start="$ROW"
        else skipped+=("${SUB}$(file_dot "$(basename "$f")")" "${SUB2}$ROW_PROBLEM"); fi
    done < <(all_cans)
    # Files that are not readable cans are named after the table, not in it.
    # (On the normal output, so the warning stays in its place on the page.)
    [ "${#skipped[@]}" -eq 0 ] \
        || { say ""; msg_lines "$B_WARN" "Skipped can(s) that are not readable or malformed:" "${skipped[@]}"; }
    line="$(last_applied)"
    if [ -n "$line" ]; then
        id="$(log_field "$line" can)"
        more=("${SUB}${line:0:16}, system files $(log_field "$line" system)")
        # The log remembers the can after it was deleted ("delete", or by hand).
        find_can "$id" >/dev/null || more+=("${SUB}This can is no longer in $(to_tilde "$(backup_dir)")")
        say ""
        info "Latest applied on this computer: can $(show_id "$id")" "${more[@]}"
    fi
}

# can_table_head -> the heading row of a table of cans ("list", "delete").
can_table_head() { table_head 6 "ID" 7 "KIND" 16 "CREATED" 12 "HOST" 14 "MINT / CINN." -8 "SIZE" 0 "LABEL"; }

# can_row START FILE -> one row of that table for the can in FILE, after
#   START (ROW, or the "Latest:" of "list"). When the can cannot be read,
#   nothing is printed: it fails and ROW_PROBLEM says why.
ROW_PROBLEM=""
can_row() {
    local f="$2" size created kind
    tar -xzOf "$f" ./manifest.txt > "$CC_TMP/m.txt" 2>/dev/null \
        || { ROW_PROBLEM="The file cannot be unpacked"; return 1; }
    read_manifest "$CC_TMP/m.txt"
    manifest_complete || { ROW_PROBLEM="Its manifest is incomplete"; return 1; }
    size="$(human_size "$(stat -c %s "$f")")"
    created="${MAN[can.created]:0:16}"
    # "manual" in blue: a can you made yourself (blue like the dot of
    # your own items); an autocan keeps the normal colour.
    kind="$(printf '%-7s' "${MAN[can.kind]}")"
    kind="${kind/#manual/${C_BLUE}manual${C_RESET}}"
    printf '%s%s %s %-16s %-12s %-14s %8s %s\n' "$1" "$(show_id "${MAN[can.id]}")" \
        "$kind" "${created/T/ }" "${MAN[can.hostname]}" \
        "${MAN[can.mint_release]} / ${MAN[can.cinnamon_version]}" "$size" "$(short_label "${MAN[can.label]:-}")"
}

# log_field LINE NAME -> the value of NAME=... in a log line.
log_field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | tr -d '"' | head -n 1; }


# ---------------------------------------------------------------------------
# peek
# ---------------------------------------------------------------------------

cmd_peek() {
    [ $# -eq 1 ] || die "Usage: cinnamon-can peek CAN"
    local can tree
    can="$(resolve_can "$1")" || exit 1
    make_tmpdir
    tree="$CC_TMP/can"
    open_can "$can" "$tree"
    load_items "$tree/catalog/builtin" "$tree/catalog/user"

    # Only what the can holds. What differs from this computer (versions,
    # software and themes not installed here) is shown by "diff CAN".
    say ""
    can_header "Peeking into the can $(show_id "${MAN[can.id]}") ..."
    say ""
    summarize_tree "Items in the can:" "$tree"
    show_software "$tree"
}
