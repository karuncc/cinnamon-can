# lib/manage.sh -- the "label" and "delete" commands: look after your cans.
#
#   label CAN TEXT        give a can another label ("" removes it)
#   delete CAN [CAN ...]  delete cans, after you type "yes"
#
# A label lives in the can's manifest.txt. "label" swaps only that one
# file inside the can: the ID, the file name and everything else in the
# can stay exactly as they were.
#
# "delete" removes the can files for good (they do not go to the Trash).
# The log keeps the lines of seal and open, so a deleted can's ID is
# never given to a new can, and "list" says when the can applied last is
# gone.

# shellcheck source=lib/list.sh
source "$CC_ROOT/lib/list.sh"


# ---------------------------------------------------------------------------
# label
# ---------------------------------------------------------------------------

cmd_label() {
    [ $# -eq 2 ] || die "Usage: cinnamon-can label CAN TEXT" \
        "To remove the label, give an empty TEXT:" "\$ cinnamon-can label CAN \"\""
    local can id old tarball part
    can="$(resolve_can "$1")" || exit 1
    clean_label "$2"
    make_tmpdir

    # Unzip the can and read its manifest (the same checks as every command).
    tarball="$CC_TMP/can.tar"
    gzip -dc "$can" > "$tarball" 2>/dev/null && tar -tf "$tarball" >/dev/null 2>&1 \
        || not_a_can "$can" damaged
    tar -xOf "$tarball" ./manifest.txt > "$CC_TMP/manifest.txt" 2>/dev/null \
        || not_a_can "$can" no-manifest
    read_manifest "$CC_TMP/manifest.txt"
    manifest_complete || not_a_can "$can" incomplete
    id="${MAN[can.id]}" old="${MAN[can.label]:-}"

    say ""
    if [ "$old" = "$LABEL" ]; then
        info "The can $(show_id "$id") already has this label; nothing was changed." \
             "${SUB}Label: $(label_or_none "$old")"
        return 0
    fi
    [ -w "$(dirname "$can")" ] \
        || die "The can $(show_id "$id") cannot be changed: its folder is not writable" \
               "${SUB}$(file_dot "$(to_tilde "$can")")"

    # The new manifest replaces the old one inside the archive; nothing
    # else is unpacked, so every other file keeps its exact permissions.
    mkdir -p "$CC_TMP/new"
    set_label "$CC_TMP/manifest.txt" "$LABEL" > "$CC_TMP/new/manifest.txt"
    { tar --delete -f "$tarball" ./manifest.txt && tar -C "$CC_TMP/new" -rf "$tarball" ./manifest.txt; } \
        || die "Could not put the new label into the can; it was not changed"

    # Written next to the can first, then put in its place in one step,
    # with the can's own permissions and time (Ctrl+C is off for that step).
    part="$can.part"
    track_partial "$part"
    gzip -c "$tarball" > "$part" || die "Could not write the changed can next to it"
    chmod --reference="$can" "$part"
    touch -r "$can" "$part"
    trap '' INT
    mv -f "$part" "$can"
    forget_partial "$part"
    trap on_ctrl_c INT

    ok "The label of the can $(show_id "$id") is changed:" \
       "${SUB}Was: $(label_or_none "$old")" \
       "${SUB}Now: $(label_or_none "$LABEL")"
}

# set_label MANIFEST TEXT -> the manifest with TEXT on its "label" line
#   (a manifest without one gets it right under "[can]"). The text is
#   handed over through the environment, so a "\" in it stays a "\".
set_label() {
    CC_LABEL="$2" awk '
        function put() { printf "label            = %s\n", ENVIRON["CC_LABEL"]; done = 1 }
        NR == FNR { if ($0 ~ /^\[.*\]$/) s = $0; else if (s == "[can]" && $0 ~ /^[ \t]*label[ \t]*=/) has = 1; next }
        /^\[.*\]$/ { s = $0 }
        s == "[can]" && /^[ \t]*label[ \t]*=/ { if (!done) put(); next }
        { print }
        $0 == "[can]" && !has { put() }' "$1" "$1"
}


# ---------------------------------------------------------------------------
# delete
# ---------------------------------------------------------------------------

cmd_delete() {
    [ $# -ge 1 ] || die "Usage: cinnamon-can delete CAN [CAN ...]"
    make_tmpdir
    CC_CANCEL_NOTE="Cancelled; nothing was deleted."
    local what can f t way_back="" last back answer which
    local -a cans=() failed=()
    for what in "$@"; do
        can="$(resolve_can "$what")" || exit 1
        # Only files named like a can: a mistyped path never deletes
        # anything else. (A can that cannot be read may be deleted.)
        [[ "$(basename "$can")" =~ $CAN_NAME_RE ]] \
            || die "Only cans can be deleted; this file is not one:" "${SUB}$(file_dot "$(to_tilde "$can")")"
        # The same can named twice (by its ID and by its path): once.
        for f in "${cans[@]+"${cans[@]}"}"; do [ "$f" != "$can" ] || continue 2; done
        cans+=("$can")
    done

    # The autocan saved by the latest "open" here is the way back from it.
    last="$(last_applied)"
    back="$(log_field "$last" backup)"

    say ""
    info "Cans to be deleted:"
    can_table_head
    for can in "${cans[@]}"; do
        if ! can_row "$ROW" "$can"; then
            # What the file name tells, and why the rest is not shown.
            [[ "$(basename "$can")" =~ $CAN_NAME_RE ]]
            t="${BASH_REMATCH[3]}"
            printf '%s%s %-7s %-16s %s%s%s\n' "$ROW" "$(show_id "${BASH_REMATCH[2]}")" "${BASH_REMATCH[1]}" \
                "${t:0:4}-${t:4:2}-${t:6:2} ${t:9:2}:${t:11:2}" "$C_GREY" "$ROW_PROBLEM" "$C_RESET"
        fi
        [ -z "$back" ] || [ "$(can_id "$can")" != "$back" ] || way_back="$back"
    done
    if [ -n "$way_back" ]; then
        say ""
        warn "The can $(show_id "$way_back") is the way back from the latest open:" \
             "${SUB}It holds this computer's settings from before the can $(show_id "$(log_field "$last" can)") was opened."
    fi

    say ""
    [ -t 0 ] || die "Command \"delete\" needs to be confirmed in a terminal"
    which="this can"; [ "${#cans[@]}" -eq 1 ] || which="these ${#cans[@]} cans"
    # (Ctrl+D ends the input: read fails, which counts as "no".)
    read -r -p "${MSG_INDENT}Type \"yes\" to delete $which for good: " answer || { say ""; answer=""; }
    [ "$answer" = "yes" ] || { info "Cancelled; nothing was deleted."; return 1; }

    trap '' INT
    for can in "${cans[@]}"; do
        rm -f -- "$can" 2>/dev/null || true
        [ ! -e "$can" ] || failed+=("${SUB}$(file_dot "$(to_tilde "$can")")")
    done
    trap on_ctrl_c INT
    if [ "${#failed[@]}" -eq "${#cans[@]}" ]; then die "Could not delete:" "${failed[@]}"
    elif [ "${#failed[@]}" -gt 0 ]; then die "Could not delete these; the others are deleted:" "${failed[@]}"; fi
    if [ "${#cans[@]}" -eq 1 ]; then ok "The can $(show_id "$(can_id "${cans[0]}")") is deleted."
    else ok "The ${#cans[@]} cans are deleted."; fi
}
