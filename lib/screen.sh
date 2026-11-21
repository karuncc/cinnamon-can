# lib/screen.sh -- how cinnamon-can writes to the screen.
#
# This file is not run on its own: lib/common.sh loads it. In it:
#
#   1. Messages and colours: the two columns, badges, tables, long text
#   2. Text from a can: control characters written as plain letters
#   3. Commands to copy, paths and sizes as they are shown
#   4. Long reports: the pager


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
    local LC_ALL=C.UTF-8            # (letters, not bytes: see fit_start)
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
# 2. Text from a can
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# 3. Commands to copy, paths and sizes
# ---------------------------------------------------------------------------

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

# human_size BYTES -> e.g. "3.4 MB"
human_size() {
    awk -v b="$1" 'BEGIN { split("B KB MB GB", u, " "); i = 1
        while (b >= 1024 && i < 4) { b /= 1024; i++ }
        if (i == 1) printf "%d %s\n", b, u[i]; else printf "%.1f %s\n", b, u[i] }'
}


# ---------------------------------------------------------------------------
# 4. Long reports: the pager
# ---------------------------------------------------------------------------

# show_paged FILE -> shows FILE page by page when this is a terminal: with
#   $PAGER if you set one (like git does), otherwise "less" (which quits
#   by itself when everything fits on one screen). FILE has colour codes
#   in it. "less" only shows them as colours with its -R option, so a
#   PAGER that is less gets it through LESS, less's own setting for
#   options: added to yours, or, like git does when you have none, the
#   same -RFX the program uses itself. Any other pager gets the text
#   without colour codes, so it is always readable. A PAGER that is not
#   installed is said so, and the text is shown without it. How the pager
#   ends (some end with an error code when you quit them) never changes
#   what the command ends with.
show_paged() {
    local cmd esc=$'\e'
    if [ ! -t 1 ]; then
        cat "$1"
    elif [ -n "${PAGER:-}" ]; then
        read -r cmd _ <<< "$PAGER"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "The pager in PAGER is not installed: $(visible "$cmd")" "The text follows without it."
            cat "$1"
        elif [ "${cmd##*/}" = "less" ]; then
            if [ -n "${LESS:-}" ]; then LESS="-R $LESS" $PAGER "$1" || true
            else LESS="-RFX" $PAGER "$1" || true; fi
        else
            sed "s/${esc}\[[0-9;]*m//g" "$1" > "$1.plain"
            $PAGER "$1.plain" || true
        fi
    elif command -v less >/dev/null 2>&1; then
        less -RFX "$1" || true
    else
        cat "$1"
    fi
}
