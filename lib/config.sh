# lib/config.sh -- the config file, and reading INI files.
#
# This file is not run on its own: lib/common.sh loads it. In it:
#
#   1. Reading INI files (the config, item files, the settings in a can)
#   2. The config file and the backup folder


# ---------------------------------------------------------------------------
# 1. Reading INI files
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


# ---------------------------------------------------------------------------
# 2. The config file
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
    local section name lines value wrong problems=() unknown=" "
    while IFS=$'\t' read -r section name lines value; do
        if [[ "$section" == !* ]]; then
            section="${section#!}"
            problems+=("${SUB2}L${section%%:*}:${section#*:}"); continue
        fi
        case "$section.$name" in
            general.backup_dir)
                if [ -z "$value" ]; then problems+=("${SUB2}L$lines: Setting \"backup_dir\" is empty")
                elif wrong="$(backup_dir_problem "$value")"; then problems+=("${SUB2}L$lines: $wrong")
                else CONF_BACKUP_DIR="$value"; fi ;;
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

# backup_dir_problem VALUE -> what is wrong with a backup_dir value, or
#   nothing (and false) when it is fine. Only ~ (your home folder), ~/...
#   and a full path (/...) can be meant: anything else would be taken
#   from whatever folder you run the command in, so cans would end up
#   scattered. The usual mistakes get a hint:
#     "/my cans"    -> no quotes needed, also with spaces
#     $HOME/cans    -> ~/cans (no variables are filled in)
#     cans, ./cans  -> did you mean ~/cans?
#     ~alex/cans    -> ~ stands only for your own home folder
backup_dir_problem() {
    local v="$1" shown bare
    case "$v" in "~"|"~/"*|/*) return 1 ;; esac
    to_visible shown "$v"
    local it="Setting \"backup_dir\""
    case "$v" in
        [\"\']*|*[\"\'])
            # Without the quotes it may be fine (then say so), or have a
            # mistake of its own (then name that one).
            bare="${v#[\"\']}"; bare="${bare%[\"\']}"
            if [ -n "$bare" ] && ! backup_dir_problem "$bare" >/dev/null; then
                to_visible bare "$bare"
                printf '%s needs no quotes, also with spaces in it: write %s' "$it" "$bare"
            elif [ -n "$bare" ]; then
                backup_dir_problem "$bare"
            else
                printf '%s must start with ~/ or / (a full path), not "%s"' "$it" "$shown"
            fi ;;
        '$HOME'|'${HOME}')     printf '%s cannot use $HOME: write ~' "$it" ;;
        '$HOME/'*|'${HOME}/'*) to_visible bare "~/${v#*/}"
                               printf '%s cannot use $HOME: write %s' "$it" "$bare" ;;
        *'$'*)                 printf '%s cannot use variables ("%s"): write the full path' "$it" "$shown" ;;
        "~"*)                  printf '%s: ~ stands only for your own home folder (~/...), not "%s"' "$it" "$shown" ;;
        .|..|../*|*:*|*\\*)    printf '%s must start with ~/ or / (a full path), not "%s"' "$it" "$shown" ;;
        *)                     to_visible bare "~/${v#./}"
                               printf '%s must start with ~/ or / (a full path), not "%s"; did you mean %s?' "$it" "$shown" "$bare" ;;
    esac
    return 0
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

# ensure_backup_dir [check] -> makes sure a can can be written into the
#   backup folder, or stops with what is wrong. Only a folder the program
#   makes itself is made private (only you: 700). A folder you already
#   have keeps its permissions: you may share it on purpose (with a group,
#   a sync program), and the cans and the log in it are private files
#   anyway (600). A folder you cannot write to (one you made read-only,
#   or someone else's) is never changed: the command stops instead.
#   With "check", a missing folder is not made yet, only checked: "seal"
#   and "open" check before their work, so they stop early, and a run
#   that is cancelled leaves no empty folder behind. Any more arguments
#   are lines added to the message, saying why the command needs it.
ensure_backup_dir() {
    local dir up check="${1:-}"
    [ $# -eq 0 ] || shift
    dir="$(backup_dir)"
    if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
        if [ "$check" = "check" ]; then
            # The nearest folder above that exists must let you make it.
            up="$(dirname -- "$dir")"
            while [ ! -e "$up" ] && [ "$up" != "/" ] && [ "$up" != "." ]; do up="$(dirname -- "$up")"; done
            [ -d "$up" ] && [ -w "$up" ] && [ -x "$up" ] \
                || die "Cannot create the backup folder $(to_tilde "$dir")" "(backup_dir in $(conf_name 25))" "$@"
            return 0
        fi
        mkdir -p -- "$dir" 2>/dev/null \
            || die "Cannot create the backup folder $(to_tilde "$dir")" "(backup_dir in $(conf_name 25))" "$@"
        # (A USB stick formatted FAT or exFAT has no permissions to set.)
        chmod 700 -- "$dir" 2>/dev/null || true
    fi
    [ -d "$dir" ] || [ ! -e "$dir" ] \
        || die "The backup folder $(to_tilde "$dir") is a file, not a folder" "(backup_dir in $(conf_name 25))" "$@"
    [ -d "$dir" ] && [ -w "$dir" ] && [ -x "$dir" ] \
        || die "Cannot write to the backup folder $(to_tilde "$dir")" "(backup_dir in $(conf_name 25))" "$@"
    # The log is written right after the can; it must take a line too.
    [ ! -e "$(log_file)" ] || [ -w "$(log_file)" ] \
        || die "Cannot write to the log $(to_tilde "$(log_file)")" "$@"
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
