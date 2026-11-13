# lib/list.sh -- the "list" and "peek" commands, and reading cans.
#
#   list        every can in the backup folder, newest first
#   peek CAN    what is inside one can

# shellcheck source=lib/refs.sh
source "$CC_ROOT/lib/refs.sh"

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
    tar -C "$dir" -xzf "$can" 2>/dev/null || die "$(to_tilde "$can") is damaged or not a can"
    [ -f "$dir/manifest.txt" ] || die "$(to_tilde "$can") has no manifest; it was not made by cinnamon-can"
    read_manifest "$dir/manifest.txt"
    manifest_complete || die "$(to_tilde "$can") has a broken manifest; it was not made by cinnamon-can"
}

# tree_items TREE -> the items stored in a tree, in catalog order.
tree_items() {
    local n
    for n in "${ITEM_NAMES[@]}"; do [ -d "$1/items/$n" ] && printf '%s\n' "$n"; done
    return 0
}

# version_notes -> what differs between the opened can (MAN) and this
#   computer, one line each (nothing when it all matches).
version_notes() {
    [ "${MAN[can.mint_release]:-}" = "$SYS_RELEASE" ] || echo "Linux Mint ${MAN[can.mint_release]:-?} in the can, $SYS_RELEASE here"
    [ "${MAN[can.mint_edition]:-}" = "$SYS_EDITION" ] || echo "${MAN[can.mint_edition]:-?} edition in the can, $SYS_EDITION here"
    [ "${MAN[can.cinnamon_version]:-}" = "$SYS_CINNAMON" ] || echo "Cinnamon ${MAN[can.cinnamon_version]:-?} in the can, $SYS_CINNAMON here"
    [ "${MAN[can.arch]:-}" = "$SYS_ARCH" ] || echo "${MAN[can.arch]:-?} in the can, $SYS_ARCH here"
    return 0
}

# can_header PATH -> the first lines of peek / diff / open about a can.
can_header() {
    say "${C_BOLD}${MAN[can.id]}${C_RESET}  ${MAN[can.kind]}  ${MAN[can.label]:+\"${MAN[can.label]}\"}"
    say "Made ${MAN[can.created]} on ${MAN[can.hostname]} — Linux Mint ${MAN[can.mint_release]} ${MAN[can.mint_edition]}, Cinnamon ${MAN[can.cinnamon_version]}, ${MAN[can.arch]}"
    [ -z "${MAN[can.opened]:-}" ] || say "Saved automatically just before opening can ${MAN[can.opened]}"
}

# summarize_tree TREE -> one line per item: settings, files, extras.
summarize_tree() {
    local tree="$1" n d settings files extra
    printf '%s  %-16s %8s %6s%s\n' "$C_DIM" "item" "settings" "files" "$C_RESET"
    while IFS= read -r n; do
        d="$tree/items/$n"
        settings=0; files=0; extra=""
        [ -f "$d/dconf.ini" ] && settings="$(ini_flat "$d/dconf.ini" | wc -l)"
        files="$( { find "$d/home" "$d/root" \( -type f -o -type l \) 2>/dev/null || true; } | wc -l)"
        [ -d "$d/wallpaper" ] && extra="$extra  + wallpaper $(basename "$(cat "$d/wallpaper.txt" 2>/dev/null)")"
        [ -f "$d/language.txt" ] && extra="$extra  $(tr '\n' ' ' < "$d/language.txt")"
        [ -f "$d/timezone.txt" ] && extra="$extra  time zone $(cat "$d/timezone.txt")"
        [ -f "$d/crontab.txt" ] && extra="$extra  + crontab"
        [ -f "$d/software.txt" ] && extra="$extra  $(software_counts "$d/software.txt")"
        printf '  %-16s %8s %6s%s\n' "$n" "$settings" "$files" "$extra"
    done < <(tree_items "$tree")
}

# software_section FILE SECTION -> the lines of one [section] of software.txt
software_section() {
    awk -v s="[$2]" '/^\[/ { on = ($0 == s); next } on && NF' "$1"
}

software_counts() {
    printf '%s apps, %s language packages, %s flatpaks' \
        "$(software_section "$1" apps | wc -l)" \
        "$(software_section "$1" language-support | wc -l)" \
        "$(software_section "$1" flatpak | wc -l)"
}

# show_software TREE -> the full software list of a tree.
show_software() {
    local f
    f="$( { find "$1/items" -name software.txt 2>/dev/null || true; } | head -n 1)"
    [ -n "$f" ] || return 0
    title "Software (reference only, never installed for you)"
    printf '  %-17s %s\n' "Apps" "$(software_section "$f" apps | tr '\n' ' ')"
    printf '  %-17s %s\n' "Language support" "$(software_section "$f" language-support | tr '\n' ' ')"
    printf '  %-17s %s\n' "Flatpak" "$(software_section "$f" flatpak | awk '{ print $1 }' | tr '\n' ' ')"
    printf '  %-17s %s\n' "Local programs" "$(software_section "$f" local-programs | tr '\n' ' ')"
    printf '  %-17s %s\n' "Sources" "$(software_section "$f" sources | awk -F'\t' '{ print $1 }' | tr '\n' ' ')"
}


# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

cmd_list() {
    [ $# -eq 0 ] || die "list takes no arguments"
    make_tmpdir
    local f n=0 size created line
    title "Cans in $(to_tilde "$(backup_dir)")"
    while IFS= read -r f; do
        if [ "$n" -eq 0 ]; then
            printf '%s%-5s %-7s %-17s %-12s %-14s %8s  %s%s\n' "$C_DIM" "ID" "KIND" "CREATED" "HOST" \
                "MINT / CINN." "SIZE" "LABEL" "$C_RESET"
        fi
        n=$((n + 1))
        tar -xzOf "$f" ./manifest.txt > "$CC_TMP/m.txt" 2>/dev/null || { warn "cannot read $(basename "$f")"; continue; }
        read_manifest "$CC_TMP/m.txt"
        manifest_complete || { warn "$(basename "$f") has a broken manifest; skipped"; continue; }
        size="$(human_size "$(stat -c %s "$f")")"
        created="${MAN[can.created]:0:16}"
        printf '%-5s %-7s %-17s %-12s %-14s %8s  %s\n' "${MAN[can.id]}" "${MAN[can.kind]}" "${created/T/ }" \
            "${MAN[can.hostname]}" "${MAN[can.mint_release]} / ${MAN[can.cinnamon_version]}" "$size" \
            "${MAN[can.label]:-}"
    done < <(all_cans)

    if [ "$n" -eq 0 ]; then
        say "  no cans yet — make one with:  cinnamon-can seal"
        return 0
    fi
    line="$(last_applied)"
    if [ -n "$line" ]; then
        say ""
        say "Latest applied on this computer: $(log_field "$line" can)  (${line:0:16}, system files $(log_field "$line" system))"
    fi
}

# log_field LINE NAME -> the value of NAME=... in a log line.
log_field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | tr -d '"' | head -n 1; }


# ---------------------------------------------------------------------------
# peek
# ---------------------------------------------------------------------------

cmd_peek() {
    [ $# -eq 1 ] || die "usage: cinnamon-can peek CAN"
    local can tree notes
    can="$(resolve_can "$1")" || exit 1
    make_tmpdir
    tree="$CC_TMP/can"
    open_can "$can" "$tree"
    load_items "$tree/catalog/builtin" "$tree/catalog/user"

    say ""
    can_header
    notes="$(version_notes)"
    [ -z "$notes" ] || { say "${C_YELLOW}Differs from this computer:${C_RESET}"; printf '%s\n' "$notes" | sed 's/^/  - /'; }

    title "Items"
    summarize_tree "$tree"
    show_software "$tree"

    title "Missing on this computer"
    check_refs "$tree" > "$CC_TMP/refs.txt"
    show_missing "$CC_TMP/refs.txt" "$tree"
}
