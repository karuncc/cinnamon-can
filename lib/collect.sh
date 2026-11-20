# lib/collect.sh -- read this computer into a folder ("tree").
#
# collect_tree OUT ITEM... reads the given items and writes:
#
#   OUT/catalog/builtin/*.item   every item file known right now, so a can
#   OUT/catalog/user/*.item      can always be read the way it was made
#   OUT/items/ITEM/dconf.ini     the item's settings ("dconf load" format)
#   OUT/items/ITEM/home/...      the item's files, same paths as in ~
#   OUT/items/ITEM/root/...      system files (e.g. root/etc/default/locale)
#   OUT/items/ITEM/wallpaper/    the wallpaper image   + wallpaper.txt
#   OUT/items/ITEM/language.txt  display language and formats
#   OUT/items/ITEM/timezone.txt  time zone
#   OUT/items/ITEM/software.txt  the apps you installed
#   OUT/items/ITEM/crontab.txt   your crontab
#
# seal, diff and open all read the computer with this same code, so a can
# and the live computer are always compared like with like.
#
# What you cannot read is left out, but never silently. Your desktop and
# your apps run as you, so they cannot read it either: it makes no
# difference to how the desktop looks and feels. (It is usually left over
# from a program once run with sudo.) Each file or folder like that gets
# one line in the file UNREADABLE names:
#
#   item<TAB>kind<TAB>full path     kind: file, folder, system, wallpaper
#
# (a folder's path ends with "/"), and the command shows the list with
# show_unreadable: "seal" leaves them out of the can, "diff" does not
# compare them, and "open" leaves them as they are (drop_unreadable in
# lib/diff.sh). So "open" never writes over or deletes what the autocan
# could not keep a copy of.
UNREADABLE=""

collect_tree() {
    local out="$1" n; shift
    make_tmpdir
    UNREADABLE="$CC_TMP/unreadable.txt"; : > "$UNREADABLE"
    mkdir -p "$out/items" "$out/catalog/builtin" "$out/catalog/user"
    for n in "${ITEM_NAMES[@]}"; do
        cp "${ITEM_FILE[$n]}" "$out/catalog/${ITEM_SRC[$n]}/$n.item"
    done
    for n in "$@"; do mkdir -p "$out/items/$n"; done

    collect_dconf "$out" "$@"
    collect_files "$out" "$@"
    for n in "$@"; do
        collect_system "$out" "$n"
        item_has "$n" wallpaper && collect_wallpaper "$out/items/$n" "$n"
        item_has "$n" language  && read_language > "$out/items/$n/language.txt"
        item_has "$n" timezone  && read_timezone > "$out/items/$n/timezone.txt"
        item_has "$n" software  && write_software_list > "$out/items/$n/software.txt"
        item_has "$n" crontab   && collect_crontab "$out/items/$n"
    done
    return 0
}

# --- Settings database ------------------------------------------------------

collect_dconf() {
    local out="$1" n split="$CC_TMP/dconf-split"; shift
    rm -rf "$split"; mkdir -p "$split"
    dconf dump / > "$CC_TMP/dconf-dump.txt" || die "Could not read the settings database (dconf dump)"
    write_dconf_patterns "$CC_TMP/dconf-patterns.txt"
    awk -f "$CC_ROOT/lib/dconf.awk" -v outdir="$split" -v want="$*" \
        "$CC_TMP/dconf-patterns.txt" "$CC_TMP/dconf-dump.txt"
    for n in "$@"; do
        [ -f "$split/$n.ini" ] && mv "$split/$n.ini" "$out/items/$n/dconf.ini"
    done
    rm -rf "$split"
}

# --- Files in your home folder ----------------------------------------------

collect_files() {
    local out="$1" n p abs m rel; shift
    local cand="$CC_TMP/file-candidates.txt" own="$CC_TMP/file-owners.txt"
    local list="$CC_TMP/file-list.txt" got="$CC_TMP/file-got.txt"
    : > "$cand"; : > "$CC_TMP/closed-folders.txt"
    write_file_patterns "$CC_TMP/file-patterns.txt"

    # Everything that exists for the items asked for.
    for n in "$@"; do
        while IFS= read -r p; do
            abs="$(expand_home "$p")"
            if [[ "$abs" == *[*?]* ]]; then
                # (a folder that cannot be opened simply matches nothing)
                closed_glob_folder "$abs" "$n"
                while IFS= read -r m; do add_candidate "$m" "$p" "$n"; done < <(compgen -G "$abs" || true)
            else
                add_candidate "$abs" "$p" "$n"
            fi
        done < <(split_words "${ITEM_FILES[$n]}")
    done
    sort -u -o "$cand" "$cand"

    # Who owns each file (longest pattern of ALL items), minus exclusions.
    awk -f "$CC_ROOT/lib/files.awk" "$CC_TMP/file-patterns.txt" "$cand" > "$own"
    note_closed_folders "$@"

    # Copy, item by item, keeping symlinks, permissions and file times.
    for n in "$@"; do
        awk -F'\t' -v i="$n" -v h="$HOME/" '$1 == i { print substr($2, length(h) + 1) }' "$own" > "$list"
        [ -s "$list" ] || continue
        mkdir -p "$out/items/$n/home"
        tar -C "$HOME" --no-recursion --ignore-failed-read -cf - -T "$list" 2>/dev/null \
            | tar -C "$out/items/$n/home" -xf -
        # A file that did not arrive could not be read (unless it was
        # deleted in the meantime: then there is nothing to keep).
        { ( cd "$out/items/$n/home" && find . \( -type f -o -type l \) ) || true; } | sed 's|^\./||' | sort > "$got"
        while IFS= read -r rel; do
            [ -e "$HOME/$rel" ] || [ -L "$HOME/$rel" ] || continue
            printf '%s\tfile\t%s\n' "$n" "$HOME/$rel" >> "$UNREADABLE"
        done < <(sort "$list" | comm -23 - "$got")
    done
}

# add_candidate PATH PATTERN ITEM -> lists PATH (a file) or everything
#   under it (a folder) in the candidates file. A folder that cannot be
#   opened (not readable, or not enterable) is listed in closed-folders.txt
#   instead, with ITEM, and nothing below it is looked at.
add_candidate() {
    local m="$1" p="$2" n="$3"
    if [ -d "$m" ] && [[ "$m" == */ || "$p" == */ ]]; then
        if [ ! -r "$m" ] || [ ! -x "$m" ]; then
            printf '%s\t%s/\n' "$n" "${m%/}" >> "$CC_TMP/closed-folders.txt"
            return 0
        fi
        # "D" for a folder inside that cannot be opened (find does not go
        # into it), "F" for a file. A file that a program deletes while
        # find looks makes find complain; that is no reason to stop.
        { find "${m%/}/" -mindepth 1 \
               \( -type d \( ! -readable -o ! -executable \) -printf 'D\t%p/\n' -prune \) \
               -o \( -type f -o -type l \) -printf 'F\t%p\n' 2>/dev/null || true; } \
            | awk -v n="$n" -v cand="$CC_TMP/file-candidates.txt" -v closed="$CC_TMP/closed-folders.txt" '
                /^D\t/ { print n "\t" substr($0, 3) >> closed; next }
                       { print substr($0, 3) >> cand }'
    elif [ -f "$m" ] || [ -L "$m" ]; then
        printf '%s\n' "$m" >> "$CC_TMP/file-candidates.txt"
    else
        closed_on_the_way "$m" "$n" "$HOME"
    fi
    return 0
}

# closed_on_the_way PATH ITEM TOP -> PATH was not found. That is only
#   certain when the nearest folder above it (below TOP) can be entered;
#   if it cannot, PATH may well be in there, and that folder is listed in
#   closed-folders.txt with ITEM.
closed_on_the_way() {
    local d="${1%/}" n="$2" top="$3"
    d="${d%/*}"
    while [ -n "$d" ] && [ "$d" != "$top" ] && [[ "$d" == "$top"/* || "$top" == "/" ]]; do
        if [ -e "$d" ]; then
            [ ! -d "$d" ] || [ -x "$d" ] || printf '%s\t%s/\n' "$n" "$d" >> "$CC_TMP/closed-folders.txt"
            return 0
        fi
        d="${d%/*}"
    done
    return 0
}

# closed_glob_folder PATTERN ITEM -> for a pattern with * or ?: the folder
#   it looks in (up to the first wildcard) must be readable and enterable,
#   or nothing in it can match; if not, that folder is listed instead.
closed_glob_folder() {
    local d="${1%%[*?]*}" n="$2"
    d="${d%/*}"
    if [ -d "$d" ]; then
        [ -r "$d" ] && [ -x "$d" ] || printf '%s\t%s/\n' "$n" "$d" >> "$CC_TMP/closed-folders.txt"
    else
        closed_on_the_way "$d/" "$n" "$HOME"
    fi
    return 0
}

# note_closed_folders ITEM... -> the folders in closed-folders.txt go to
#   UNREADABLE, each with the item that would own what is inside it: the
#   same rules as for files (lib/files.awk), so a folder that its item
#   leaves out on purpose (exclude) is not named. A folder no item's
#   pattern covers (one on the way to a single file) keeps the item that
#   named the file. Only the items asked for (ITEM...) count.
note_closed_folders() {
    local closed="$CC_TMP/closed-folders.txt" paths="$CC_TMP/closed-paths.txt"
    [ -s "$closed" ] || return 0
    cut -f2- "$closed" | sort -u > "$paths"
    awk -f "$CC_ROOT/lib/files.awk" "$CC_TMP/file-patterns.txt" "$paths" > "$paths.owners"
    { grep '^inc' "$CC_TMP/file-patterns.txt" || true; } > "$paths.inc"
    awk -f "$CC_ROOT/lib/files.awk" "$paths.inc" "$paths" > "$paths.claimed"
    awk -F'\t' -v want=" $* " -v owners="$paths.owners" -v claimed="$paths.claimed" '
        FILENAME == owners  { owner[$2] = $1; next }
        FILENAME == claimed { taken[$2] = 1; next }
        {   p = substr($0, length($1) + 2)
            if (p in done) next
            done[p] = 1
            if (p in owner) n = owner[p]
            else if (p in taken) next          # left out on purpose
            else n = $1
            if (index(want, " " n " ")) print n "\tfolder\t" p
        }' "$paths.owners" "$paths.claimed" "$closed" >> "$UNREADABLE"
}

# --- System files (outside home) --------------------------------------------

collect_system() {
    local out="$1" n="$2" p
    while IFS= read -r p; do
        if [ -f "$p" ] && [ -r "$p" ]; then
            mkdir -p "$out/items/$n/root$(dirname "$p")"
            cp -p "$p" "$out/items/$n/root$p"
        elif [ -e "$p" ]; then
            printf '%s\tsystem\t%s\n' "$n" "$p" >> "$UNREADABLE"
        else
            # (a folder on the way that cannot be entered hides it)
            : > "$CC_TMP/closed-folders.txt"
            closed_on_the_way "$p" "$n" "/"
            [ ! -s "$CC_TMP/closed-folders.txt" ] \
                || awk -F'\t' -v OFS='\t' '{ print $1, "system", $2 }' "$CC_TMP/closed-folders.txt" >> "$UNREADABLE"
        fi
    done < <(split_words "${ITEM_SYSTEM[$n]}")
}

# --- Special sources ---------------------------------------------------------

# The wallpaper setting only holds a path. The image is kept too, because
# the other computer may not have it.
#   collect_wallpaper DIR ITEM
collect_wallpaper() {
    local dir="$1" n="$2" uri path
    uri="$(dconf read /org/cinnamon/desktop/background/picture-uri 2>/dev/null || true)"
    uri="${uri#\'}"; uri="${uri%\'}"
    [[ "$uri" == file://* ]] || return 0
    path="$(printf '%b' "$(printf '%s' "${uri#file://}" | sed 's/%/\\x/g')")"   # %20 -> space
    if [ -f "$path" ] && [ -r "$path" ]; then
        mkdir -p "$dir/wallpaper"
        cp -p "$path" "$dir/wallpaper/"
        printf '%s\n' "$path" > "$dir/wallpaper.txt"
    else
        # The setting is kept (it is a setting); the image only when you
        # can read it. An image that is gone is nothing to report; one you
        # cannot read, or one in a folder you cannot enter, is.
        : > "$CC_TMP/closed-folders.txt"
        [ -e "$path" ] || closed_on_the_way "$path" "$n" "/"
        if [ -e "$path" ] || [ -s "$CC_TMP/closed-folders.txt" ]; then
            printf '%s\twallpaper\t%s\n' "$n" "$path" >> "$UNREADABLE"
        fi
    fi
}

# --- What could not be read ---------------------------------------------------

# unreadable_count -> how many files and folders could not be read.
unreadable_count() {
    if [ -n "$UNREADABLE" ] && [ -s "$UNREADABLE" ]; then cut -f3- "$UNREADABLE" | sort -u | wc -l
    else echo 0; fi
}

# show_unreadable TITLE -> the warning for what could not be read (see
#   UNREADABLE), sorted by path, each with the item it is in:
#       └ ~/.config/app/locked.conf  (app-settings)
#       └ ~/.config/other/  (keyboard, the whole folder)
#   Nothing when everything could be read. Part of a report, so it goes
#   to the normal output. (Names from this computer may hold control
#   characters too; they are written as plain letters.)
show_unreadable() {
    [ "$(unreadable_count)" -gt 0 ] || return 0
    local lines=() n kind path shown what
    while IFS=$'\t' read -r n kind path; do
        to_visible shown "$(to_tilde "$path")"
        what=""
        [[ "$path" != */ ]] || what=", the whole folder"
        [ "$kind" != "wallpaper" ] || what=", the wallpaper image"
        lines+=("${SUB}$shown  ($(item_dot "$n")$n$what)")
    done < <(sort -t$'\t' -k3 -u "$UNREADABLE")
    msg_lines "$B_WARN" "$1" "${lines[@]}"
}

# read_language -> "Language=..." and "Formats=..." of your account, from
#   AccountsService (what System Settings > Languages sets for you).
read_language() {
    local prop value
    for prop in Language FormatsLocale; do
        value="$(busctl get-property org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
                    org.freedesktop.Accounts.User "$prop" 2>/dev/null | sed 's/^s "//; s/"$//' || true)"
        printf '%s=%s\n' "$prop" "$value"
    done
}

read_timezone() {
    timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true
}

collect_crontab() {
    local dir="$1"
    # "crontab -l" fails when you have no crontab; that is fine.
    crontab -l > "$dir/crontab.txt" 2>/dev/null || true
    [ -s "$dir/crontab.txt" ] || rm -f "$dir/crontab.txt"
}

# write_software_list -> the apps you installed yourself, in sections:
#   [apps] [language-support]   apt packages you chose (not their helpers)
#   [flatpak] [flatpak-remotes] Flatpak apps and where they come from
#   [local-programs]            programs in /usr/local/bin not from a package
#   [sources]                   extra apt sources
write_software_list() {
    local f top="$CC_TMP/software-top.txt" mine="$CC_TMP/software-manual.txt"

    # apt: packages marked "installed by you", minus what the Mint
    # installer put there ...
    if [ -r /var/log/installer/initial-status.gz ]; then
        comm -23 <(apt-mark showmanual 2>/dev/null | sort -u) \
                 <(gzip -dc /var/log/installer/initial-status.gz | awk '/^Package: / { print $2 }' | sort -u) \
            > "$mine" || true
    else
        apt-mark showmanual 2>/dev/null | sort -u > "$mine" || true
    fi
    # ... minus packages that another installed package needs or recommends
    # (those are helpers, not apps you chose), minus kernel packages.
    dpkg-query -W -f='${Package}\t${Depends}, ${Pre-Depends}, ${Recommends}\n' 2>/dev/null \
        | awk -F'\t' '
            FNR == NR { mine[$1] = 1; next }
            { n = split($2, d, /[,|]/)
              for (i = 1; i <= n; i++) {
                  x = d[i]; gsub(/\([^)]*\)/, "", x); gsub(/:any/, "", x); gsub(/^ +| +$/, "", x)
                  if (x != "" && x != $1) needed[x] = 1 } }
            END { for (p in mine) if (!(p in needed)) print p }' "$mine" - \
        | grep -v -E '^linux-[a-z0-9-]*[0-9]+\.[0-9]+' | sort > "$top" || true

    local lang_re='^(language-pack-|hunspell-|hyphen-|mythes-|fonts-|fcitx|ibus|gtk-im-|gir1\.2-fcitx|libreoffice-l10n-|libreoffice-help-|firefox-locale-|thunderbird-locale-)'
    echo "[apps]";             grep -v -E "$lang_re" "$top" || true
    echo "[language-support]"; grep -E "$lang_re" "$top" || true

    echo "[flatpak]"
    if command -v flatpak >/dev/null 2>&1; then
        flatpak list --app --columns=application,origin 2>/dev/null || true
    fi
    echo "[flatpak-remotes]"
    if command -v flatpak >/dev/null 2>&1; then
        flatpak remotes --columns=name,url 2>/dev/null || true
    fi

    echo "[local-programs]"
    for f in /usr/local/bin/*; do
        [ -f "$f" ] || continue
        dpkg -S "$f" >/dev/null 2>&1 || printf '%s\n' "$f"
    done

    echo "[sources]"
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [ -f "$f" ] || continue                     # (skips .save and other copies)
        [ "$(basename "$f")" = "official-package-repositories.list" ] && continue   # Mint's own
        printf '%s\t%s\n' "$(basename "$f")" \
            "$(awk '/^URIs:/ { print $2; exit } /^deb / { for (i = 2; i <= NF; i++) if ($i ~ /:\/\//) { print $i; exit } }' "$f")"
    done
}
