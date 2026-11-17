# lib/manage.sh -- the "label" command: look after your cans.
#
#   label CAN TEXT        give a can another label ("" removes it)
#
# A label lives in the can's manifest.txt. "label" swaps only that one
# file inside the can: the ID, the file name and everything else in the
# can stay exactly as they were.

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
