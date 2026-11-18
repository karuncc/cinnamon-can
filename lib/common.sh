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

C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_BOLD="" C_GREY="" C_RESET=""
CC_COLS=""
if [ -t 1 ]; then
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m'
    C_BOLD=$'\e[1m' C_GREY=$'\e[90m' C_RESET=$'\e[0m'
    # The width of the terminal, for lines that must fit on one screen line.
    CC_COLS="$(stty size </dev/tty 2>/dev/null | cut -d" " -f2)" || true
fi

# The screen has two columns. The left one (9 characters) holds a status
# badge or stays empty; everything else starts in the right one:
#
#      INFO  Reading this computer's settings ...
#     ERROR  Invalid config file(s) detected:
#            └ • config/default.conf
#              └ L3: Expected "name = value", got: not a setting line
#            Run "cinnamon-can help" for the commands.
#
# In a terminal a badge is a coloured block; otherwise (a pipe, a file) the
# same word without colour, so both look alike.
if [ -t 1 ]; then
    B_INFO=$'\e[1;97;44m'"   INFO "$'\e[0m'" "     # white on blue
    B_OK=$'\e[1;30;42m'"     OK "$'\e[0m'" "       # black on green
    B_WARN=$'\e[1;30;43m'"   WARN "$'\e[0m'" "     # black on yellow
    B_ERROR=$'\e[1;97;41m'"  ERROR "$'\e[0m'" "    # white on red
else
    B_INFO="   INFO  " B_OK="     OK  " B_WARN="   WARN  " B_ERROR="  ERROR  "
fi
MSG_INDENT="         "

# Other marks in the left column:
#   a command for you to type gets a grey "$" there, so the command itself
#   starts in the right column and can be copied as it is:
#          $ cinnamon-can seal
#   (every message line that starts with "$ " is shown this way);
#   a changed line of a comparison gets a "-" or "+" block (B_MINUS /
#   B_PLUS); a file that is new or deleted gets "[NEW]" or "[DEL]" (green
#   or red words, no block, so they do not look like the "+" and "-"
#   blocks; the same kind of mark as "[DONE]" and "[SUDO REQUIRED]"); the
#   way back after "open" gets an UNDO badge, with an empty line above and
#   below, so it stands out. Only the terminal's own colours are used.
CMD_COL="       ${C_GREY}\$${C_RESET} "
if [ -t 1 ]; then
    B_MINUS=$'\e[1;97;41m'" - "$'\e[0m'                      # white on red
    B_PLUS=$'\e[1;30;42m'" + "$'\e[0m'                       # black on green
    B_NEW="   "$'\e[1;32m'"[NEW]"$'\e[0m'" "                    # green words
    B_DEL="   "$'\e[1;31m'"[DEL]"$'\e[0m'" "                    # red words
    B_UNDO=$'\e[1;97;45m'"   UNDO "$'\e[0m'" "                 # white on magenta
else
    B_MINUS=" - " B_PLUS=" + " B_NEW="   [NEW] " B_DEL="   [DEL] " B_UNDO="   UNDO  "
fi
# What only "sudo cinnamon-can open" can change: the mark after its name,
# and the colour of its dot in the summary of "diff" (yellow, like WARN).
C_SUDO="$C_YELLOW"
B_SUDO="${C_SUDO}[SUDO REQUIRED]${C_RESET}"

# value_word TEXT -> TEXT, but "(default)" (a setting that was never
#   changed) in grey, so it does not read like a value.
value_word() {
    if [ "$1" = "(default)" ]; then printf '%s(default)%s' "$C_GREY" "$C_RESET"
    else visible "$1"; fi     # (the value may come from a can)
}

# line_counts_text PLUS MINUS -> "(+3 | -1)" for the lines a file gains
#   and loses: the numbers green and red in a terminal, grey when 0.
line_counts_text() {
    local p="$C_GREEN" m="$C_RED"
    [ "$1" -gt 0 ] || p="$C_GREY"; [ "$2" -gt 0 ] || m="$C_GREY"
    printf '(%s+%s%s | %s-%s%s)' "$p" "$1" "$C_RESET" "$m" "$2" "$C_RESET"
}

# A line that belongs to the line above it starts with a grey "└":
#   SUB  for the first level, SUB2 for a line under such a line.
SUB="${C_GREY}└${C_RESET} "
SUB2="  ${C_GREY}└${C_RESET} "

# say LINE -> one line in the right column ("$ command": see CMD_COL).
say() {
    case "$*" in
        "")     printf '\n' ;;
        "\$ "*) printf '%s%s\n' "$CMD_COL" "${*#"\$ "}" ;;
        *)      printf '%s%s\n' "$MSG_INDENT" "$*" ;;
    esac
}

# The four kinds of status message. Each argument is one line: the first
# follows the badge, the others start under it, in the right column.
info()  { msg_lines "$B_INFO" "$@"; }                                   # progress, notes
ok()    { msg_lines "$B_OK" "$@"; }                                     # success
warn()  { msg_lines "$B_WARN" "$@" >&2; }                               # notice
err()   { msg_lines "$B_ERROR" "$@" >&2; }                              # problem
die()   { err "$@"; exit 1; }                                           # stop now

# msg_lines PREFIX FIRST [MORE ...] -> PREFIX FIRST, then each MORE indented.
msg_lines() {
    local prefix="$1" line; shift
    printf '%s%s\n' "$prefix" "${1:-}"; shift || true
    for line in "$@"; do say "$line"; done
}

# show_id ID -> a can's ID made easy to spot: on a grey block in a terminal,
#   in [brackets] otherwise. Both are 2 characters wider than the ID.
#   (Not used inside commands you may copy.)
show_id() {
    if [ -n "$C_RESET" ]; then printf '%s %s %s' $'\e[1;97;100m' "$1" "$C_RESET"
    else printf '[%s]' "$1"; fi
}

# table_head WIDTH TEXT [WIDTH TEXT ...] -> a table's heading row, in grey.
#   A table sits under a message, and each row starts with "└ " (ROW);
#   the heading row starts with a small grey dot "• " in the same place
#   (the node the rows hang from), so the headings stand over their
#   columns. A negative WIDTH puts the text on the right (for numbers).
table_head() {
    local w t cell row="" n pad
    while [ $# -ge 2 ]; do
        w="$1" t="$2"; shift 2
        # Count characters, not bytes ("•" is one character but 3 bytes).
        n="$(printf '%s' "$t" | LC_ALL=C tr -d '\200-\277' | wc -c)"
        pad="$(printf '%*s' $(( ${w#-} > n ? ${w#-} - n : 0 )) '')"
        if [ "$w" -lt 0 ]; then cell="$pad$t"; else cell="$t$pad"; fi
        row+="$cell "
    done
    row="${row% }"
    printf '%s%s• %s%s\n' "$MSG_INDENT" "$C_GREY" "${row%"${row##*[! ]}"}" "$C_RESET"
}
ROW="$MSG_INDENT$SUB"     # the start of a table row

# file_dot NAME -> a file name in a list, with a yellow dot in front so the
#   eye finds the files among the lines under them.
file_dot() { printf '%s•%s %s' "$C_YELLOW" "$C_RESET" "$1"; }

# screen_width -> how many characters fit on one line: the terminal's
#   width (read at start-up), or 80 when the output is not a terminal.
screen_width() {
    local w="${CC_COLS:-}"
    [[ "$w" =~ ^[0-9]+$ ]] && [ "$w" -ge 40 ] || w=80
    printf '%s\n' "$w"
}

# fit_end TEXT ROOM -> TEXT as it is when it fits in ROOM characters, else
#   only its end with "…" in front (for long paths: the file name stays).
#   Without a terminal the text is never cut, so nothing is lost in a file.
fit_end() {
    if [ -n "$C_RESET" ] && [ "${#1}" -gt "$2" ]; then printf '…%s' "${1: -$(( $2 - 1 ))}"
    else printf '%s' "$1"; fi
}

# fit_start TEXT ROOM -> the same, but the start stays and "…" goes at the
#   end (for a label: its first words stay). Characters are counted as
#   letters, not bytes, whatever language the computer is set to.
fit_start() {
    local LC_ALL=C.UTF-8
    if [ -n "$C_RESET" ] && [ "${#1}" -gt "$2" ]; then printf '%s…' "${1:0:$(( $2 - 1 ))}"
    else printf '%s' "$1"; fi
}


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
    CC_TMP="$(mktemp -d "$base/cinnamon-can.XXXXXXXX")" || die "Cannot create a temporary folder in $base"
    chmod 700 "$CC_TMP"
    trap cleanup EXIT
    trap on_ctrl_c INT
    trap 'exit 130' TERM
}

# What Ctrl+C says before the program stops. A command changes it when
# stopping at that point means something else ("seal": no can was made).
# While "open" writes, Ctrl+C is switched off, so nothing is half done.
CC_CANCEL_NOTE="Cancelled; nothing was changed."

# on_ctrl_c -> a new line (the terminal leaves the cursor after "^C"),
#   the note above, then stop; cleanup still runs. Written to stderr, so
#   it reaches the screen even while a report is being written to a file.
on_ctrl_c() {
    { printf '\n'; info "$CC_CANCEL_NOTE"; } >&2
    exit 130
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
#   Prints one line per setting:   section<TAB>name<TAB>lines<TAB>value
#   ("lines" is where the setting stands in the file: 3, or 3-4 when its
#   value goes on over the next line; it comes before the value because a
#   value can be empty), or "!<line>: <problem>" for a line that makes no
#   sense.
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
#     backup_dir = ~/cans              general<TAB>backup_dir<TAB>3<TAB>~/cans
#
#   Written for plain POSIX awk (mawk), which is what Mint ships.

parse_ini() {
    awk -v dflt="${2:-}" '
        function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        function nocomment(s) { sub(/[ \t]+#.*$/, "", s); return s }
        function flush() {
            if (have) print section "\t" name "\t" (last > first ? first "-" last : first) "\t" value
            have = 0
        }
        BEGIN { section = dflt }
        {
            line = trim(nocomment($0))
            if (line == "" || line ~ /^[#;]/) next
            if (have && $0 ~ /^[ \t]/ && line !~ /^\[/) {        # continuation
                value = (value == "") ? line : value " " line
                last = NR
                next
            }
            flush()
            if (line ~ /^\[.*\]$/) { section = trim(substr(line, 2, length(line) - 2)); next }
            eq = index(line, "=")
            if (eq == 0)       { print "!" NR ": Expected \"name = value\", got: " line; next }
            if (section == "") { print "!" NR ": Setting found before any [section]"; next }
            name = trim(substr(line, 1, eq - 1)); value = trim(substr(line, eq + 1))
            if (name == "")    { print "!" NR ": Missing name before \"=\""; next }
            have = 1; first = NR; last = NR
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
CC_CONFIG_ARG=""               # what you typed after -c (empty: none)
CONF_BACKUP_DIR="~/cinnamon-cans"
declare -A CONF_ITEMS=()       # item name -> yes | no
declare -A CONF_ITEM_LINES=()  # item name -> its line(s) in the config
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
            die "No config found at config/default.conf" \
                "Create your own default config file using:" \
                "\$ cd $(shell_word "$(to_tilde "$CC_ROOT")")" \
                "\$ cp config/example.conf config/default.conf"
        fi
        die "Provided config file not found: $(conf_name 41)"
    fi
    USER_ITEMS_DIR="$(cd "$(dirname "$CONF_FILE")" && pwd)/items"

    # Every problem is collected first, so all of them are shown at once,
    # each with the line(s) it is on:   L6: shell must be yes or no ...
    local section name lines value problems=() unknown=" "
    while IFS=$'\t' read -r section name lines value; do
        if [[ "$section" == !* ]]; then
            section="${section#!}"
            problems+=("${SUB2}L${section%%:*}:${section#*:}"); continue
        fi
        case "$section.$name" in
            general.backup_dir)
                if [ -n "$value" ]; then CONF_BACKUP_DIR="$value"
                else problems+=("${SUB2}L$lines: Setting \"backup_dir\" is empty"); fi ;;
            items.*)
                CONF_ITEM_LINES[$name]="$lines"
                if [ "$value" = "yes" ] || [ "$value" = "no" ]; then CONF_ITEMS[$name]="$value"
                else problems+=("${SUB2}L$lines: Item \"$name\" must be yes or no, not \"$value\""); fi ;;
            general.*)
                problems+=("${SUB2}L$lines: Unknown setting \"$name\" in [general]") ;;
            *)
                # One line per unknown section is enough; it names the line
                # of the [section] heading itself.
                [[ "$unknown" == *" $section "* ]] && continue
                unknown+="$section "
                lines="$(awk -v s="[$section]" '{ t = $0; gsub(/^[ \t]+|[ \t\r]+$/, "", t) }
                                                t == s { print NR; exit }' "$CONF_FILE")" || true
                problems+=("${SUB2}L${lines:-?}: Unknown section [$section]") ;;
        esac
    done < <(parse_ini "$CONF_FILE")
    [ "${#problems[@]}" -eq 0 ] || config_problems "${problems[@]}"
}

# config_problems LINE... -> stops with every problem of the config file,
#   listed under its name (the same layout as for item files).
config_problems() {
    die "Invalid config file(s) detected:" "${SUB}$(file_dot "$(conf_name 13)")" "$@"
}

# conf_name USED -> the config file's name as messages show it, cut at the
#   front when it would not fit on the line (you name the file yourself,
#   so it may be long); USED is how much of the line is taken before it.
#   At least 10 characters of it stay, even on a very narrow screen.
conf_name() {
    local room=$(( $(screen_width) - $1 ))
    [ "$room" -ge 10 ] || room=10
    fit_end "$(rel_path "$CONF_FILE")" "$room"
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
    local problems=() tool
    if [ ! -r /etc/linuxmint/info ]; then
        problems+=("${SUB}This does not look like Linux Mint (/etc/linuxmint/info is missing)")
    elif [ "$SYS_EDITION" != "Cinnamon" ]; then
        problems+=("${SUB}This is Linux Mint ${SYS_EDITION:-?}; cinnamon-can only supports the Cinnamon edition")
    fi
    [ -n "$SYS_CINNAMON" ] || problems+=("${SUB}Could not find Cinnamon (\"cinnamon --version\" failed)")
    for tool in dconf tar gzip awk diff cmp find xargs; do
        command -v "$tool" >/dev/null 2>&1 || problems+=("${SUB}Required program \"$tool\" is missing")
    done
    [ "${#problems[@]}" -eq 0 ] || die "This computer cannot run cinnamon-can:" "${problems[@]}"

    case "$SYS_RELEASE" in
        22.*) ;;
        *) warn "Linux Mint $SYS_RELEASE has not been tested; cinnamon-can is made for Mint 22.x" ;;
    esac
    [ "${XDG_SESSION_TYPE:-}" != "wayland" ] || warn "This is a Wayland session; cinnamon-can is tested on X11 only"
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

# Control characters are invisible letters that a terminal takes as
# orders instead of showing them: change the colour, move the cursor,
# erase a line. This program sends such orders itself (the coloured
# badges), but text that comes from a can must never send them: anyone
# can edit a can, and its label could then erase lines of "list" or paint
# "checked, safe" in green. So text from a can is shown with each control
# character written as plain letters, the way "cat -v" writes them: ESC
# as ^[, a carriage return as ^M, the 8-bit form of ESC [ as M-^[. Tabs
# and line breaks stay as they are. Labels and the other fields of a
# manifest lose them altogether (read_manifest, clean_label).
CTRL_FROM=() CTRL_TO=() CTRL_SET=""
for _i in {1..8} {11..31} 127 {128..159}; do
    printf -v _o '%03o' "$_i"
    if [ "$_i" -lt 128 ]; then
        printf -v _c "\\$_o"
        if [ "$_i" -eq 127 ]; then _l='?'; else printf -v _o '%03o' $((_i + 64)); printf -v _l "\\$_o"; fi
        CTRL_TO+=("^$_l")
    else
        # 128-159: the same orders in their 8-bit form, as UTF-8 writes them
        printf -v _c "\\302\\$_o"
        printf -v _o '%03o' $((_i - 64)); printf -v _l "\\$_o"
        CTRL_TO+=("M-^$_l")
    fi
    CTRL_FROM+=("$_c"); CTRL_SET+="$_c"
done
unset _i _o _c _l

# to_visible VAR TEXT -> sets VAR to TEXT with its control characters
#   written as plain letters (see above). visible TEXT prints that.
to_visible() {
    local _t="$2" _k
    if [[ "$_t" == *["$CTRL_SET"]* ]]; then
        for _k in "${!CTRL_FROM[@]}"; do _t="${_t//"${CTRL_FROM[$_k]}"/"${CTRL_TO[$_k]}"}"; done
    fi
    printf -v "$1" '%s' "$_t"
}
visible() { local _v; to_visible _v "$1"; printf '%s' "$_v"; }

# The same for awk: a program that starts with "$CTRL_AWK" has vis(s)
# (control characters written as plain letters) and novis(s) (removed).
# (Plain text search instead of gsub: some marks contain a "\".)
CTRL_AWK='
BEGIN {
    for (ci = 1; ci < 32; ci++) if (ci != 9 && ci != 10) { CF[++CN] = sprintf("%c", ci); CT[CN] = "^" sprintf("%c", ci + 64) }
    CF[++CN] = sprintf("%c", 127); CT[CN] = "^?"
    for (ci = 128; ci < 160; ci++) { CF[++CN] = sprintf("%c%c", 194, ci); CT[CN] = "M-^" sprintf("%c", ci - 64) }
}
function ctrl_swap(s, strip,   k, p) {
    for (k = 1; k <= CN; k++)
        while ((p = index(s, CF[k])) > 0) s = substr(s, 1, p - 1) (strip ? "" : CT[k]) substr(s, p + length(CF[k]))
    return s
}
function vis(s) { return ctrl_swap(s, 0) }
function novis(s) { return ctrl_swap(s, 1) }
'

# shell_word WORD -> WORD written so that it can be typed (or pasted) into
#   a terminal as one word: as it is when it holds only plain characters,
#   else in single quotes. A leading "~/" stays outside the quotes, so the
#   terminal still reads it as your home folder. Control characters are
#   written as plain letters (to_visible): they can never be typed anyway.
#   Examples:  ~/repos/cinnamon-can     ~/'My Programs/cinnamon can'
shell_word() {
    local w start=""
    to_visible w "$1"
    [ "$w" != "~" ] || { printf '~'; return 0; }
    case "$w" in "~/"*) start="~/" w="${w#\~/}" ;; esac
    if [[ "$w" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]]; then printf '%s%s' "$start" "$w"
    else printf "%s'%s'" "$start" "${w//\'/\'\\\'\'}"; fi
}

# config_option -> " -c CONFIG" when the program was started with -c, so a
#   command to copy uses the same config (and finds the same cans);
#   nothing otherwise. A config named by its path is written in full, so
#   the command also works from another folder.
config_option() {
    [ -n "$CC_CONFIG_ARG" ] || return 0
    if [[ "$CC_CONFIG_ARG" == */* || "$CC_CONFIG_ARG" == *.conf ]]; then
        printf ' -c %s' "$(shell_word "$(to_tilde "$(cd "$(dirname "$CONF_FILE")" && pwd)/$(basename "$CONF_FILE")")")"
    else
        printf ' -c %s' "$(shell_word "$CC_CONFIG_ARG")"
    fi
}

# show_path KIND REL -> how a path inside an item of a can is shown:
#   home/... as ~/..., root/... as /..., crontab.txt as "crontab"
#   (a file name may come from a can: see to_visible)
show_path() {
    local p
    to_visible p "$2"
    case "$p" in
        home/*)      printf '~/%s' "${p#home/}" ;;
        root/*)      printf '/%s' "${p#root/}" ;;
        crontab.txt) printf 'crontab' ;;
        *)           printf '%s' "$p" ;;
    esac
}

# rel_path PATH -> a path inside the program's folder written from there
#   (config/default.conf, items/sound.item), as "help" writes them; any
#   other path with ~ for your home folder.
rel_path() {
    case "$1" in
        "$CC_ROOT"/*) printf '%s\n' "${1#"$CC_ROOT"/}" ;;
        *)            to_tilde "$1" ;;
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
