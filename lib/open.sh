# lib/open.sh -- the "open" command: make this computer match a can.
#
#   cinnamon-can open CAN          your settings and files
#   sudo cinnamon-can open CAN     ... and the system files too
#
# In order:
#   1. Show the same comparison as "diff CAN" (with a warning on top when
#      the can comes from another Mint / Cinnamon version).
#   2. Ask you to type "yes". Anything else changes nothing.
#   3. Save the current state as a new "autocan", so it can be undone
#      with "cinnamon-can open <that ID>".
#   4. Write: files first (so applets find their settings files), then the
#      settings database, the language, the system files (only with sudo),
#      and ask fcitx to reload. Files the can does not have are deleted
#      (they were listed as "deleted" in the comparison); system files are
#      never deleted.
#   5. Write the log, show how to undo, and restart the computer after a
#      10-second countdown (Ctrl+C cancels the restart).

# shellcheck source=lib/diff.sh
source "$CC_ROOT/lib/diff.sh"
# shellcheck source=lib/seal.sh
source "$CC_ROOT/lib/seal.sh"

cmd_open() {
    [ $# -eq 1 ] || die "Usage: cinnamon-can open CAN"
    make_tmpdir
    local with_system="${CC_SYSTEM_RESTORE:-0}" can_id answer problems=0 system_state

    build_comparison "$1"
    can_id="$CMP_PLUS_ID"
    show_paged "$CMP_REPORT"

    if [ "$CMP_TOTAL" -eq 0 ]; then
        say ""; ok "This computer's settings already match the can $(show_id "$can_id")"
        return 0
    fi
    # sudo does not search ~/.local/bin, so always show the full path.
    local sudo_cmd="sudo $(to_tilde "$CC_ROOT/cinnamon-can") open $can_id"
    if [ "$CMP_SYSTEM" -gt 0 ] && [ "$with_system" != "1" ]; then
        say ""
        if [ "$CMP_SYSTEM" -eq "$CMP_TOTAL" ]; then
            # Nothing else differs: asking and restarting would change nothing.
            info "Only system files and settings differ; they need sudo." "To restore them, run:" "\$ $sudo_cmd"
            return 0
        fi
        warn "$CMP_SYSTEM system change(s) will NOT be made without sudo." \
             "To include them, stop here and run:" "\$ $sudo_cmd"
    fi

    say ""
    [ -t 0 ] || die "Command \"open\" needs to be confirmed in a terminal"
    # (Ctrl+D ends the input: read fails, which counts as "no", not as a silent stop.)
    read -r -p "${MSG_INDENT}Type \"yes\" to apply these changes and restart the computer: " answer || { say ""; answer=""; }
    [ "$answer" = "yes" ] || { info "Cancelled; nothing was changed."; return 1; }

    # Save the current state first, shown the same way "seal" shows a can.
    # (The "-" side of the comparison IS the current state, read moments ago.)
    package_can "$CMP_MINUS" autocan "Before opening $can_id" "$can_id"
    local undo_id="$CAN_ID"
    read_manifest "$CMP_MINUS/manifest.txt"
    say ""
    can_header "Sealing the current settings as the autocan $(show_id "$undo_id") ..."
    say ""
    show_sealed "The autocan is sealed:"

    say ""
    info "Applying changes from the can $(show_id "$can_id") to this computer ..."
    run_step "Files"    apply_files    || problems=1
    run_step "Settings" apply_settings || problems=1
    # The language only when the can changes it.
    if [ -n "$(result_paths setting changed added | grep -F '(language)' || true)" ]; then
        run_step "Language" apply_language || problems=1
    fi
    system_state="none"
    if [ "$CMP_SYSTEM" -gt 0 ]; then
        if [ "$with_system" = "1" ]; then
            run_step "System files" apply_system && system_state="restored" || { system_state="failed"; problems=1; }
        else
            system_state="skipped"
        fi
    fi
    reload_input_methods

    log_add "cmd=open  can=$can_id  backup=$undo_id  system=$system_state  result=$([ "$problems" -eq 0 ] && echo applied || echo problems)"

    say ""
    if [ "$problems" -eq 0 ]; then ok "This computer's settings now match the can $(show_id "$can_id")"
    else warn "Some changes could not be made (see above)"; fi
    [ "$system_state" != "skipped" ] || warn "System files were not changed; for them run:" "\$ $sudo_cmd"
    # The way back, on its own with an empty line above and below, so it
    # is easy to find (and to copy) even while the countdown runs.
    say ""
    msg_lines "$B_UNDO" "To go back to how this computer was, run:" "\$ cinnamon-can open $undo_id"
    say ""
    restart_countdown
}


# ---------------------------------------------------------------------------
# Applying the result list ($CMP_RESULT, see compare_views in diff.sh)
# ---------------------------------------------------------------------------

# result_paths KIND STATE... -> "item<TAB>path" of matching result lines.
#   Example: "result_paths file changed added" lists every file that
#   "open" must copy into the home folder.
result_paths() {
    local kind="$1"; shift
    awk -F'\t' -v k="$kind" -v s=" $* " '$2 == k && index(s, " " $4 " ") { print $1 "\t" $3 }' "$CMP_RESULT"
}

# Each step of writing (apply_files, apply_settings, apply_language,
# apply_system) returns 1 when something went wrong, and adds one line per
# problem to REASONS. The messages of the programs it runs (tar, dconf ...)
# are kept in APPLY_ERR, so they do not break the layout of the screen.
REASONS=()
APPLY_ERR=""

# run_step NAME FUNCTION -> runs one step, then shows its row:
#     └ • Files            [DONE]
#     └ • Settings         [FAIL]
#       └ appearance: error: The connection is closed
#   The dot and the word are green for DONE and red for FAIL. (Words, not
#   badges: a row is a detail of the "Applying changes" message.)
run_step() {
    local st=0 c="$C_GREEN" word="DONE" r
    REASONS=() APPLY_ERR="$CC_TMP/apply-err.txt"
    "$2" || st=1
    [ "$st" -eq 0 ] || { c="$C_RED"; word="FAIL"; }
    say "${SUB}${c}•${C_RESET} $(printf '%-16s' "$1") ${c}[$word]${C_RESET}"
    for r in "${REASONS[@]+"${REASONS[@]}"}"; do say "${SUB2}$r"; done
    return "$st"
}

# why WHAT TEXT -> one problem for REASONS: "WHAT: " and the first line the
#   program wrote to APPLY_ERR, or TEXT when it wrote nothing.
why() {
    local l
    l="$(head -n 1 "$APPLY_ERR" 2>/dev/null)" || true
    REASONS+=("$1: ${l:-$2}")
}

apply_files() {
    local n rel list="$CC_TMP/apply-files.txt" bad=0
    # New and changed files, copied item by item (symlinks and permissions kept).
    for n in "${CMP_ITEMS[@]}"; do
        result_paths file changed added | awk -F'\t' -v i="$n" '$1 == i { print substr($2, 6) }' > "$list"
        [ -s "$list" ] || continue
        { tar -C "$CMP_PLUS/items/$n/home" --no-recursion -cf - -T "$list" | tar -C "$HOME" -xf - ; } 2> "$APPLY_ERR" \
            || { why "$(item_dot "$n")$n" "some files could not be written"; bad=1; }
    done
    # Files the can does not have.
    while IFS=$'\t' read -r n rel; do
        rm -f -- "$HOME/${rel#home/}" 2> "$APPLY_ERR" || { why "$(item_dot "$n")$n" "~/${rel#home/} could not be removed"; bad=1; }
    done < <(result_paths file removed)
    # The crontab.
    while IFS=$'\t' read -r n rel; do
        crontab "$CMP_PLUS/items/$n/crontab.txt" 2> "$APPLY_ERR" || { why "crontab" "it could not be installed"; bad=1; }
    done < <(result_paths crontab changed added)
    while IFS=$'\t' read -r n rel; do
        crontab -r 2>/dev/null || true
    done < <(result_paths crontab removed)
    return "$bad"
}

apply_settings() {
    local n path bad=0
    for n in "${CMP_ITEMS[@]}"; do
        # Settings this computer has but the can does not: back to default.
        while IFS=$'\t' read -r _ path; do
            [[ "$path" == /* ]] || continue
            dconf reset "$path" 2> "$APPLY_ERR" || { why "$(item_dot "$n")$n" "$path could not be reset"; bad=1; }
        done < <(result_paths setting removed | awk -F'\t' -v i="$n" '$1 == i')
        if [ -f "$CMP_PLUS/items/$n/dconf.ini" ] && grep -q "^$n	setting	/" "$CMP_RESULT"; then
            dconf load / < "$CMP_PLUS/items/$n/dconf.ini" 2> "$APPLY_ERR" \
                || { why "$(item_dot "$n")$n" "the settings could not be loaded"; bad=1; }
        fi
    done
    return "$bad"
}

# The language of your account is set through AccountsService, the same
# way System Settings > Languages does it (no sudo needed).
apply_language() {
    local n path value method bad=0
    while IFS=$'\t' read -r n path; do
        value="$(awk -F'\t' -v i="$n" -v p="$path" '$1 == i && $3 == p { print $6 }' "$CMP_RESULT")"
        # "(default)" means the can has no value stored (see compare_views).
        [ -n "$value" ] && [ "$value" != "(default)" ] || continue
        case "$path" in
            "(language) Language")      method=SetLanguage ;;
            "(language) FormatsLocale") method=SetFormatsLocale ;;
            *) continue ;;
        esac
        busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
            org.freedesktop.Accounts.User "$method" s "$value" >/dev/null 2> "$APPLY_ERR" \
            || { why "${path#"(language) "} $value" "it could not be set"; bad=1; }
    done < <(result_paths setting changed added | grep -F '(language)' || true)
    return "$bad"
}

# System files: written with sudo, owned by root, keeping the mode the
# file already has here (or 644 for a new one).
apply_system() {
    local n rel dest mode tz bad=0
    while IFS=$'\t' read -r n rel; do
        dest="/${rel#root/}"
        mode="$(stat -c %a "$dest" 2>/dev/null || echo 644)"
        sudo install -D -m "$mode" -o root -g root "$CMP_PLUS/items/$n/$rel" "$dest" 2> "$APPLY_ERR" \
            || { why "$dest" "it could not be written"; bad=1; }
    done < <(result_paths system changed added)
    tz="$(awk -F'\t' '$3 == "(time zone)" && $4 != "removed" { print $6; exit }' "$CMP_RESULT")"
    if [ -n "$tz" ]; then
        sudo timedatectl set-timezone "$tz" 2> "$APPLY_ERR" || { why "Time zone $tz" "it could not be set"; bad=1; }
    fi
    return "$bad"
}

# fcitx keeps its settings in memory and could write the old ones back at
# log out; ask a running fcitx to read the restored files again.
reload_input_methods() {
    if command -v fcitx-remote >/dev/null 2>&1 && pgrep -u "$(id -u)" -x fcitx >/dev/null 2>&1; then
        fcitx-remote -r >/dev/null 2>&1 || true
    fi
    if command -v fcitx5-remote >/dev/null 2>&1 && pgrep -u "$(id -u)" -x fcitx5 >/dev/null 2>&1; then
        fcitx5-remote -r >/dev/null 2>&1 || true
    fi
}

# Restart, like Timeshift does after a restore: the desktop reads every
# setting fresh. Ctrl+C during the countdown cancels the restart only.
restart_countdown() {
    local i
    trap 'say ""; warn "Restart cancelled." "Please restart (or log out and in) yourself soon."; exit 0' INT
    for i in 10 9 8 7 6 5 4 3 2 1; do
        printf '\r%sRestarting in %2d second(s) (Ctrl+C to cancel) ' "$B_INFO" "$i"
        sleep 1
    done
    say ""
    systemctl reboot || die "Could not restart; please restart yourself"
}
