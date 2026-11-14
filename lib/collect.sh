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

collect_tree() {
    local out="$1" n; shift
    make_tmpdir
    mkdir -p "$out/items" "$out/catalog/builtin" "$out/catalog/user"
    for n in "${ITEM_NAMES[@]}"; do
        cp "${ITEM_FILE[$n]}" "$out/catalog/${ITEM_SRC[$n]}/$n.item"
    done
    for n in "$@"; do mkdir -p "$out/items/$n"; done

    collect_dconf "$out" "$@"
    collect_files "$out" "$@"
    for n in "$@"; do
        collect_system "$out" "$n"
        item_has "$n" wallpaper && collect_wallpaper "$out/items/$n"
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
    local out="$1" n p abs m item path; shift
    local cand="$CC_TMP/file-candidates.txt" own="$CC_TMP/file-owners.txt"
    : > "$cand"
    write_file_patterns "$CC_TMP/file-patterns.txt"

    # Everything that exists for the items asked for.
    for n in "$@"; do
        while IFS= read -r p; do
            abs="$(expand_home "$p")"
            if [[ "$abs" == *[*?]* ]]; then
                while IFS= read -r m; do add_candidate "$m" "$p"; done < <(compgen -G "$abs" || true)
            else
                add_candidate "$abs" "$p"
            fi
        done < <(split_words "${ITEM_FILES[$n]}")
    done
    sort -u -o "$cand" "$cand"

    # Who owns each file (longest pattern of ALL items), minus exclusions.
    awk -f "$CC_ROOT/lib/files.awk" "$CC_TMP/file-patterns.txt" "$cand" > "$own"

    # Copy, item by item, keeping symlinks, permissions and file times.
    for n in "$@"; do
        awk -F'\t' -v i="$n" -v h="$HOME/" '$1 == i { print substr($2, length(h) + 1) }' "$own" \
            > "$CC_TMP/file-list.txt"
        [ -s "$CC_TMP/file-list.txt" ] || continue
        mkdir -p "$out/items/$n/home"
        tar -C "$HOME" --no-recursion --ignore-failed-read -cf - -T "$CC_TMP/file-list.txt" 2>/dev/null \
            | tar -C "$out/items/$n/home" -xf -
    done
}

# add_candidate PATH PATTERN -> lists PATH (a file) or everything under it
#   (a folder) in the candidates file.
add_candidate() {
    local m="$1" p="$2"
    if [ -d "$m" ] && [[ "$m" == */ || "$p" == */ ]]; then
        find "${m%/}/" -mindepth 1 \( -type f -o -type l \) -print >> "$CC_TMP/file-candidates.txt" 2>/dev/null \
            || warn "Some files in $p could not be read"
    elif [ -f "$m" ] || [ -L "$m" ]; then
        printf '%s\n' "$m" >> "$CC_TMP/file-candidates.txt"
    fi
    return 0
}

# --- System files (outside home) --------------------------------------------

collect_system() {
    local out="$1" n="$2" p
    while IFS= read -r p; do
        if [ -f "$p" ] && [ -r "$p" ]; then
            mkdir -p "$out/items/$n/root$(dirname "$p")"
            cp -p "$p" "$out/items/$n/root$p"
        elif [ -e "$p" ]; then
            warn "Cannot read $p; it is left out"
        fi
    done < <(split_words "${ITEM_SYSTEM[$n]}")
}

# --- Special sources ---------------------------------------------------------

# The wallpaper setting only holds a path. The image is kept too, because
# the other computer may not have it.
collect_wallpaper() {
    local dir="$1" uri path
    uri="$(dconf read /org/cinnamon/desktop/background/picture-uri 2>/dev/null || true)"
    uri="${uri#\'}"; uri="${uri%\'}"
    [[ "$uri" == file://* ]] || return 0
    path="$(printf '%b' "$(printf '%s' "${uri#file://}" | sed 's/%/\\x/g')")"   # %20 -> space
    if [ -f "$path" ] && [ -r "$path" ]; then
        mkdir -p "$dir/wallpaper"
        cp -p "$path" "$dir/wallpaper/"
        printf '%s\n' "$path" > "$dir/wallpaper.txt"
    fi
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
