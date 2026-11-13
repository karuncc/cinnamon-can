# lib/common.sh -- helpers shared by every cinnamon-can command.
#
# This file is not run on its own. The main "cinnamon-can" script loads it
# with "source"; after that, every function below can be used.
#
#   1. Messages and colours
#   2. A private temporary folder that is always cleaned up
#   3. Reading INI files (the config, item files, manifests)
#   4. The config file
#   5. Facts about this computer and start-up checks
#   6. Cans: IDs, names, finding them, the log
#   7. Small utilities


# ---------------------------------------------------------------------------
# 1. Messages and colours
# ---------------------------------------------------------------------------
#
# Colours are used only when the output goes straight to a terminal, never
# when it is saved to a file or piped into another program.

C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_BOLD="" C_DIM="" C_RESET=""
if [ -t 1 ]; then
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RESET=$'\e[0m'
fi

say()   { printf '%s\n' "$*"; }                                         # plain line
title() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }              # heading
info()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }            # progress
ok()    { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }          # success
warn()  { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; } # notice
err()   { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }      # problem
die()   { err "$@"; exit 1; }                                           # stop now


# ---------------------------------------------------------------------------
# 2. Temporary folder
# ---------------------------------------------------------------------------
#
# make_tmpdir creates one private folder (inside $XDG_RUNTIME_DIR, which
# only you can read). It is removed when the program ends -- normally, on
# an error, or on Ctrl+C. Half-written cans registered with track_partial
# are removed too, so an interrupted run never leaves anything behind.

CC_TMP=""
CC_PARTIAL=()

cleanup() {
    local f
    for f in "${CC_PARTIAL[@]+"${CC_PARTIAL[@]}"}"; do
        rm -f -- "$f"
    done
    if [ -n "$CC_TMP" ] && [ -d "$CC_TMP" ]; then
        # Copied folders may be read-only; make them removable first.
        chmod -R u+rwX -- "$CC_TMP" 2>/dev/null || true
        rm -rf -- "$CC_TMP"
    fi
}

make_tmpdir() {
    [ -z "$CC_TMP" ] || return 0
    local base="${XDG_RUNTIME_DIR:-}"
    if [ -z "$base" ] || [ ! -d "$base" ] || [ ! -w "$base" ]; then
        base="${TMPDIR:-/tmp}"
    fi
    CC_TMP="$(mktemp -d "$base/cinnamon-can.XXXXXXXX")" || die "cannot create a temporary folder in $base"
    chmod 700 "$CC_TMP"
    trap cleanup EXIT
    trap 'exit 130' INT TERM
}

track_partial()  { CC_PARTIAL+=("$1"); }
forget_partial() {
    local f keep=()
    for f in "${CC_PARTIAL[@]+"${CC_PARTIAL[@]}"}"; do
        [ "$f" = "$1" ] || keep+=("$f")
    done
    CC_PARTIAL=("${keep[@]+"${keep[@]}"}")
}


# ---------------------------------------------------------------------------
# 3. Reading INI files
# ---------------------------------------------------------------------------
#
# parse_ini FILE [DEFAULT_SECTION]
#   Prints one line per setting:   section<TAB>name<TAB>value
#   or "!<line>: <problem>" for a line that makes no sense.
#
#   Rules (the same everywhere):
#     - lines starting with # or ; are comments
#     - "  # text" at the end of a line is a comment too
#     - [section] starts a section; settings before any section belong to
#       DEFAULT_SECTION (item files have no sections)
#     - an indented line continues the value of the line above it
#
#   Example file:                      what parse_ini prints:
#     # my config                      (nothing, a comment)
#     [general]                        (nothing yet, starts a section)
#     backup_dir = ~/cans              general<TAB>backup_dir<TAB>~/cans
#
#   Written for plain POSIX awk (mawk), which is what Mint ships.

parse_ini() {
    awk -v dflt="${2:-}" '
        function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        function nocomment(s) { sub(/[ \t]+#.*$/, "", s); return s }
        function flush() { if (have) print section "\t" name "\t" value; have = 0 }
        BEGIN { section = dflt }
        {
            line = trim(nocomment($0))
            if (line == "" || line ~ /^[#;]/) next
            if (have && $0 ~ /^[ \t]/ && line !~ /^\[/) {        # continuation
                value = (value == "") ? line : value " " line
                next
            }
            flush()
            if (line ~ /^\[.*\]$/) { section = trim(substr(line, 2, length(line) - 2)); next }
            eq = index(line, "=")
            if (eq == 0)       { print "!" NR ": expected \"name = value\", got: " line; next }
            if (section == "") { print "!" NR ": setting found before any [section]"; next }
            name = trim(substr(line, 1, eq - 1)); value = trim(substr(line, eq + 1))
            if (name == "")    { print "!" NR ": missing name before \"=\""; next }
            have = 1
        }
        END { flush() }
    ' "$1"
}

# split_words TEXT -> one word per line. Words are separated by spaces; a
#   word in double quotes may contain spaces:  "My Notes/" -> My Notes/
split_words() {
    printf '%s\n' "$1" | awk '{
        w = ""; q = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "\"") { q = !q; continue }
            if (!q && (c == " " || c == "\t")) { if (w != "") print w; w = ""; continue }
            w = w c
        }
        if (w != "") print w
    }'
}


# ---------------------------------------------------------------------------
# 4. The config file
# ---------------------------------------------------------------------------
#
#   [general]
#   backup_dir = ~/cinnamon-cans
#
#   [items]
#   language = no          # switch an item on or off
#
# The config must exist; a fresh copy of the tool refuses to run until you
# create one from config/example.conf. Every mistake is reported at once.

CONF_FILE=""
CONF_BACKUP_DIR="~/cinnamon-cans"
declare -A CONF_ITEMS=()       # item name -> yes | no
USER_ITEMS_DIR=""              # your own items: "items" next to the config

# resolve_config NAME -> nothing = config/default.conf, a plain name =
#   config/NAME.conf, anything with "/" or ending in .conf = that file.
resolve_config() {
    local name="$1"
    if [ -z "$name" ]; then
        printf '%s\n' "$CC_ROOT/config/default.conf"
    elif [[ "$name" == */* || "$name" == *.conf ]]; then
        expand_home "$name"
    else
        printf '%s\n' "$CC_ROOT/config/$name.conf"
    fi
}

load_config() {
    CONF_FILE="$(resolve_config "$1")"
    if [ ! -f "$CONF_FILE" ]; then
        if [ -z "$1" ]; then
            err "no config found at config/default.conf"
            say "Create your config first:"
            say ""
            say "    cp $CC_ROOT/config/example.conf $CC_ROOT/config/default.conf"
            exit 1
        fi
        die "config file not found: $CONF_FILE"
    fi
    USER_ITEMS_DIR="$(cd "$(dirname "$CONF_FILE")" && pwd)/items"

    local section name value problems=0
    while IFS=$'\t' read -r section name value; do
        if [[ "$section" == !* ]]; then
            err "$CONF_FILE line ${section#!}"; problems=$((problems + 1)); continue
        fi
        case "$section.$name" in
            general.backup_dir)
                if [ -n "$value" ]; then CONF_BACKUP_DIR="$value"
                else err "$CONF_FILE: backup_dir is empty"; problems=$((problems + 1)); fi ;;
            items.*)
                if [ "$value" = "yes" ] || [ "$value" = "no" ]; then CONF_ITEMS[$name]="$value"
                else err "$CONF_FILE: [items] $name = \"$value\" (expected yes or no)"; problems=$((problems + 1)); fi ;;
            general.*)
                err "$CONF_FILE: unknown setting \"$name\" in [general]"; problems=$((problems + 1)) ;;
            *)
                err "$CONF_FILE: unknown section [$section]"; problems=$((problems + 1)) ;;
        esac
    done < <(parse_ini "$CONF_FILE")
    [ "$problems" -eq 0 ] || die "please fix the config file above ($problems problem(s))"
}

# backup_dir -> the folder where cans live, with ~ expanded.
backup_dir() { expand_home "$CONF_BACKUP_DIR"; }


# ---------------------------------------------------------------------------
# 5. Facts about this computer, start-up checks
# ---------------------------------------------------------------------------

SYS_RELEASE="" SYS_EDITION="" SYS_CINNAMON="" SYS_ARCH="" SYS_HOSTNAME=""

read_mint_info() {
    awk -F= -v k="$1" '$1 == k { v = substr($0, index($0, "=") + 1); gsub(/"/, "", v); print v; exit }' \
        /etc/linuxmint/info 2>/dev/null
}

# Each "|| true" below lets a line answer "" (empty) instead of stopping
# the whole program when something is missing (for example on a computer
# that is not Linux Mint): startup_checks right after turns the empty
# answers into clear messages about what is wrong.
load_system_facts() {
    SYS_RELEASE="$(read_mint_info RELEASE)" || true
    SYS_EDITION="$(read_mint_info EDITION)" || true
    SYS_CINNAMON="$(cinnamon --version 2>/dev/null | awk '{ print $NF; exit }')" || true
    SYS_ARCH="$(uname -m)"
    SYS_HOSTNAME="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)" || true
}

startup_checks() {
    local problems=0 tool
    if [ ! -r /etc/linuxmint/info ]; then
        err "this does not look like Linux Mint (/etc/linuxmint/info is missing)"; problems=$((problems + 1))
    elif [ "$SYS_EDITION" != "Cinnamon" ]; then
        err "this is Linux Mint ${SYS_EDITION:-?}; cinnamon-can only supports the Cinnamon edition"; problems=$((problems + 1))
    fi
    [ -n "$SYS_CINNAMON" ] || { err "could not find Cinnamon (\"cinnamon --version\" failed)"; problems=$((problems + 1)); }
    for tool in dconf tar gzip awk diff cmp find xargs; do
        command -v "$tool" >/dev/null 2>&1 || { err "required program \"$tool\" is missing"; problems=$((problems + 1)); }
    done
    [ "$problems" -eq 0 ] || die "cannot continue ($problems problem(s) above)"

    case "$SYS_RELEASE" in
        22.*) ;;
        *) warn "Linux Mint $SYS_RELEASE has not been tested; cinnamon-can is made for Mint 22.x" ;;
    esac
    [ "${XDG_SESSION_TYPE:-}" != "wayland" ] || warn "this is a Wayland session; cinnamon-can is tested on X11 only"
}


# ---------------------------------------------------------------------------
# 6. Cans: IDs, names, finding them, the log
# ---------------------------------------------------------------------------
#
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
        [ "$tries" -lt 1000 ] || die "could not find a free can ID"
    done
    printf '%s\n' "$id"
}

# resolve_can WHAT -> full path of a can, given its ID (any case) or a path.
resolve_can() {
    local what="$1" id f
    [ -n "$what" ] || die "please name a can: its ID (see: cinnamon-can list) or its path"
    if [ -f "$what" ]; then
        printf '%s/%s\n' "$(cd "$(dirname "$what")" && pwd)" "$(basename "$what")"
        return 0
    fi
    id="$(printf '%s' "$what" | tr '[:lower:]' '[:upper:]')"
    if [[ "$id" =~ ^[A-Z0-9]{4}$ ]]; then
        for f in "$(backup_dir)"/*-"$id"-*.tar.gz.canned; do
            [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
        done
        die "there is no can with ID $id in $(to_tilde "$(backup_dir)") (see: cinnamon-can list)"
    fi
    die "can not found: $what"
}

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


# ---------------------------------------------------------------------------
# 7. Small utilities
# ---------------------------------------------------------------------------

# expand_home PATH -> a leading ~ replaced by your home folder.
expand_home() {
    case "$1" in
        "~")   printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

# to_tilde PATH -> your home folder written as ~ (shorter, and never shows
#   your user name).
to_tilde() {
    case "$1" in
        "$HOME")   printf '~\n' ;;
        "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
        *)         printf '%s\n' "$1" ;;
    esac
}

# human_size BYTES -> e.g. "3.4 MB"
human_size() {
    awk -v b="$1" 'BEGIN { split("B KB MB GB", u, " "); i = 1
        while (b >= 1024 && i < 4) { b /= 1024; i++ }
        if (i == 1) printf "%d %s\n", b, u[i]; else printf "%.1f %s\n", b, u[i] }'
}

# is_text FILE -> success for an empty file or one without binary data.
is_text() { [ ! -s "$1" ] || grep -qI '' "$1"; }

# replace_text FILE OLD NEW -> replaces every OLD with NEW inside FILE
#   (plain text, no patterns). A file without OLD is not touched at all;
#   the permissions and a missing last newline are kept as they were.
replace_text() {
    local f="$1" ends_with_newline=0
    [ -n "$2" ] && grep -qF -- "$2" "$f" || return 0
    [ -n "$(tail -c 1 "$f")" ] || ends_with_newline=1
    awk -v old="$2" -v new="$3" '{
        line = $0; out = ""
        while ((i = index(line, old)) > 0) {
            out = out substr(line, 1, i - 1) new; line = substr(line, i + length(old))
        }
        print out line }' "$f" > "$f.cc-tmp"
    [ "$ends_with_newline" -eq 1 ] || truncate -s -1 "$f.cc-tmp"
    cat "$f.cc-tmp" > "$f"
    rm -f "$f.cc-tmp"
}

# ini_flat FILE [ITEM] -> a "dconf load" file as one setting per line:
#   [ITEM<TAB>]/full/path/name<TAB>value
#   Example: a file holding "[org/cinnamon]" with "panels-height=40"
#   under it becomes the line   /org/cinnamon/panels-height<TAB>40
ini_flat() {
    awk -v it="${2:-}" '
        /^\[.*\]$/ { f = substr($0, 2, length($0) - 2); f = (f == "/") ? "/" : "/" f "/"; next }
        /^[ \t]*$/ { next }
        { eq = index($0, "="); if (eq == 0) next
          print (it == "" ? "" : it "\t") f substr($0, 1, eq - 1) "\t" substr($0, eq + 1) }' "$1"
}

# show_paged FILE -> shows FILE page by page when this is a terminal: with
#   $PAGER if you set one (like git does), otherwise "less" (which quits
#   by itself when everything fits on one screen).
show_paged() {
    if [ ! -t 1 ]; then
        cat "$1"
    elif [ -n "${PAGER:-}" ]; then
        $PAGER "$1"
    elif command -v less >/dev/null 2>&1; then
        less -RFX "$1"
    else
        cat "$1"
    fi
}
