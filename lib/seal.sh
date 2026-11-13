# lib/seal.sh -- the "seal" command: put the current settings into a can.
#
#   cinnamon-can seal [-L TEXT | --label=TEXT]
#
# Every switched-on item is read from this computer (lib/collect.sh) and
# packed into one file in the backup folder:
#
#   manual-K7Q2-20261113T143000+0700.tar.gz.canned
#
# "open" uses package_can too: before it changes anything, it saves the
# current settings as an "autocan" (autocan-ID-....tar.gz.canned).

# shellcheck source=lib/collect.sh
source "$CC_ROOT/lib/collect.sh"
# shellcheck source=lib/list.sh
source "$CC_ROOT/lib/list.sh"

cmd_seal() {
    local label=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -L|--label) [ $# -ge 2 ] || die "$1 needs a text"; label="$2"; shift ;;
            --label=*)  label="${1#--label=}" ;;
            *) die "seal does not take \"$1\" (see: cinnamon-can help)" ;;
        esac
        shift
    done

    # A label is one line of text (tabs and line breaks become spaces).
    label="${label//[$'\t\n\r']/ }"

    make_tmpdir
    local stage="$CC_TMP/stage"
    local -a on=()
    mapfile -t on < <(items_on)
    [ "${#on[@]}" -gt 0 ] || die "every item is switched off in $(to_tilde "$CONF_FILE")"

    info "reading this computer ..."
    collect_tree "$stage" "${on[@]}"
    package_can "$stage" manual "$label" ""
    log_add "cmd=seal  can=$CAN_ID${label:+  label=\"$label\"}"

    read_manifest "$stage/manifest.txt"
    say ""
    can_header
    title "Items"
    summarize_tree "$stage"
    title "Missing on this computer"
    check_refs "$stage" > "$CC_TMP/refs.txt"
    show_missing "$CC_TMP/refs.txt" "$stage"
    say ""
    ok "sealed $(to_tilde "$CAN_PATH")  ($(human_size "$(stat -c %s "$CAN_PATH")"))"
    say "   ID: ${C_BOLD}$CAN_ID${C_RESET}"
}

# package_can STAGE KIND LABEL OPENED
#   Writes the manifest into STAGE and packs it into a new can. Sets
#   CAN_ID and CAN_PATH. The can is written under a temporary name first,
#   so an interrupted run never leaves a half can behind.
CAN_ID="" CAN_PATH=""
package_can() {
    local stage="$1" kind="$2" label="$3" opened="$4" dir part n
    dir="$(backup_dir)"
    mkdir -p "$dir" || die "cannot create the backup folder $dir"
    chmod 700 "$dir" 2>/dev/null || true

    CAN_ID="$(new_can_id)"
    CAN_PATH="$dir/$kind-$CAN_ID-$(date +%Y%m%dT%H%M%S%z).tar.gz.canned"
    {
        echo "# cinnamon-can manifest"
        echo "[can]"
        echo "id               = $CAN_ID"
        echo "kind             = $kind"
        echo "label            = $label"
        echo "created          = $(date -Iseconds)"
        echo "tool_version     = $CC_VERSION"
        echo "hostname         = $SYS_HOSTNAME"
        echo "user             = $(id -un)"
        echo "home             = $HOME"
        echo "mint_release     = $SYS_RELEASE"
        echo "mint_edition     = $SYS_EDITION"
        echo "cinnamon_version = $SYS_CINNAMON"
        echo "arch             = $SYS_ARCH"
        [ -z "$opened" ] || echo "opened           = $opened"
        echo
        echo "[items]"
        for n in "${ITEM_NAMES[@]}"; do
            [ -d "$stage/items/$n" ] && printf '%-16s = yes\n' "$n"
        done
        true
    } > "$stage/manifest.txt"

    part="$CAN_PATH.part"
    track_partial "$part"
    tar -C "$stage" -czf "$part" .
    chmod 600 "$part"
    mv "$part" "$CAN_PATH"
    forget_partial "$part"
}
