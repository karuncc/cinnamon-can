# lib/cans.sh -- cans: their IDs and file names, finding one, labels, the
# log.
#
# This file is not run on its own: lib/common.sh loads it.

# A can is one file:   KIND-ID-YYYYMMDDTHHMMSS+ZZZZ.tar.gz.canned
#   KIND  manual (made by seal) or autocan (made by open, before it changes
#         anything, so the change can be undone)
#   ID    4 characters from CAN_ID_CHARS. Characters that are easy to mix
#         up (1 I L O 0) are never used. You may type an ID in lower case.

CAN_ID_CHARS="23456789ABCDEFGHJKMNPQRSTUVWXYZ"
CAN_NAME_RE='^(manual|autocan)-([2-9A-HJKMNP-Z]{4})-([0-9]{8}T[0-9]{6}[+-][0-9]{4})\.tar\.gz\.canned$'

log_file() { printf '%s/cinnamon-can.log\n' "$(backup_dir)"; }

# all_cans -> full paths of every can in the backup folder, newest first.
all_cans() {
    local dir f base
    dir="$(backup_dir)"
    for f in "$dir"/*.tar.gz.canned; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        [[ "$base" =~ $CAN_NAME_RE ]] || continue
        printf '%s\t%s\n' "${BASH_REMATCH[3]:0:15}" "$f"
    done | sort -r | cut -f2-
}

# can_id PATH -> the ID part of a can's file name.
can_id()   { [[ "$(basename "$1")" =~ $CAN_NAME_RE ]] && printf '%s\n' "${BASH_REMATCH[2]}"; }

# new_can_id -> an ID not used by any can in the folder or in the log.
new_can_id() {
    local id i n tries=0 used
    used="$( { all_cans | while IFS= read -r f; do can_id "$f" || true; done
               grep -o -E '(can|backup)=[A-Z0-9]{4}' "$(log_file)" 2>/dev/null | cut -d= -f2 || true; } | sort -u )"
    while :; do
        id=""
        for n in $(od -An -N4 -tu1 /dev/urandom); do
            i=$(( n % ${#CAN_ID_CHARS} ))
            id="$id${CAN_ID_CHARS:i:1}"
        done
        printf '%s\n' "$used" | grep -qx "$id" || break
        tries=$((tries + 1))
        [ "$tries" -lt 1000 ] || die "Could not find a free can ID"
    done
    printf '%s\n' "$id"
}

# find_can ID -> full path of the can with that ID in the backup folder;
#   nothing (and a failure) when there is none.
find_can() {
    local f
    for f in "$(backup_dir)"/*-"$1"-*.tar.gz.canned; do
        [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
    done
    return 1
}

# resolve_can WHAT -> full path of a can, given its ID (any case) or a path.
resolve_can() {
    local what="$1" id f
    [ -n "$what" ] || die "Please name a can: its ID (see: cinnamon-can list) or its path"
    if [ -f "$what" ]; then
        printf '%s/%s\n' "$(cd "$(dirname "$what")" && pwd)" "$(basename "$what")"
        return 0
    fi
    id="$(printf '%s' "$what" | tr '[:lower:]' '[:upper:]')"
    if [[ "$id" =~ ^[A-Z0-9]{4}$ ]]; then
        if f="$(find_can "$id")"; then printf '%s\n' "$f"; return 0; fi
        die "There is no can with ID $(show_id "$id") in $(to_tilde "$(backup_dir)") (see: cinnamon-can list)"
    fi
    die "Can file not found: $what"
}

# can_ref FILE ID -> how a command to copy names that can: by its ID when
#   the ID finds this very file in the backup folder, else by its path (a
#   can opened from a USB stick, for example).
can_ref() {
    local f
    if f="$(find_can "$2")" && [ "$f" -ef "$1" ]; then printf '%s' "$2"
    else shell_word "$(to_tilde "$1")"; fi
}

# A label is one short line of text you give a can (seal -L, label).
LABEL_MAX=40

# clean_label TEXT -> sets LABEL to TEXT as one line (tabs and line breaks
#   become spaces, other control characters are left out), or stops when
#   it is longer than LABEL_MAX characters.
#   Characters, not bytes: a Thai letter counts as one, and so does a
#   vowel or tone mark written above or below it.
LABEL=""
clean_label() {
    local LC_ALL=C.UTF-8 text="${1//[$'\t\n\r']/ }" c
    for c in "${CTRL_FROM[@]}"; do text="${text//"$c"/}"; done
    [ "${#text}" -le "$LABEL_MAX" ] \
        || die "The label is too long: ${#text} characters (at most $LABEL_MAX)"
    LABEL="$text"
}

# short_label TEXT -> a label as tables and headings show it: at most
#   LABEL_MAX characters, so an older can (or a manifest changed by hand)
#   with a longer label cannot stretch the line. "peek" shows it whole.
short_label() { fit_start "$1" "$LABEL_MAX"; }

# log_add FIELDS... -> one line in the log: time, computer, user, fields.
#   Example line:
#   2026-11-13T14:30:00+0700  host=mylaptop  user=alex  cmd=seal  can=K7Q2
log_add() {
    local dir
    dir="$(backup_dir)"
    mkdir -p "$dir"
    printf '%s  host=%s  user=%s  %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$SYS_HOSTNAME" "$(id -un)" "$*" \
        >> "$(log_file)"
    chmod 600 "$(log_file)" 2>/dev/null || true
}

# last_applied -> the log line of the latest "open" on this computer.
last_applied() {
    [ -f "$(log_file)" ] || return 0
    grep -F "host=$SYS_HOSTNAME " "$(log_file)" | grep -F ' cmd=open ' | tail -n 1 || true
}
