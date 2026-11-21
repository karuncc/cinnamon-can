# lib/common.sh -- helpers shared by every cinnamon-can command.
#
# This file is not run on its own. The main "cinnamon-can" script loads it
# with "source"; after that, every function below, and in the three files
# it loads first, can be used:
#
#   lib/screen.sh   messages, colours and the layout of the screen, text
#                   from a can, commands to copy, the pager
#   lib/config.sh   reading INI files, the config file, the backup folder
#   lib/cans.sh     can IDs and file names, finding a can, labels, the log
#
# In this file:
#
#   1. A private temporary folder that is always cleaned up
#   2. Facts about this computer and start-up checks
#   3. Paths and files

# shellcheck source=lib/screen.sh
source "$CC_ROOT/lib/screen.sh"
# shellcheck source=lib/config.sh
source "$CC_ROOT/lib/config.sh"
# shellcheck source=lib/cans.sh
source "$CC_ROOT/lib/cans.sh"


# ---------------------------------------------------------------------------
# 1. Temporary folder
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
# 2. Facts about this computer, start-up checks
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
    SYS_CINNAMON="$(cinnamon --version 2>/dev/null | awk 'NR == 1 { v = $NF } END { print v }')" || true
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
    for tool in dconf tar gzip awk diff cmp find fc-list busctl timedatectl dpkg-query apt-mark; do
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
# 3. Paths and files
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

# rel_path PATH -> a path inside the program's folder written from there
#   (config/default.conf, items/sound.item), as "help" writes them; any
#   other path with ~ for your home folder.
rel_path() {
    case "$1" in
        "$CC_ROOT"/*) printf '%s\n' "${1#"$CC_ROOT"/}" ;;
        *)            to_tilde "$1" ;;
    esac
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
