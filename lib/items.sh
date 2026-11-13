# lib/items.sh -- items: the small files that say what to keep.
#
# An item is one file, NAME.item, describing one part of the desktop:
#
#   description = Keyboard layouts, all shortcuts, repeat speed
#   default     = on              # on | off when the config says nothing
#   dconf       = /org/cinnamon/desktop/keybindings/     (settings)
#   files       = ~/.xinputrc  ~/.config/fcitx/conf/      (files in home)
#   exclude     = ~/.config/fcitx/conf/fcitx-clipboard.config
#   system      = /etc/default/locale                     (needs sudo)
#   special     = wallpaper | language | timezone | software | crontab
#   ignore      = ~/.config/nemo/desktop-metadata:nemo-icon-view-layout-timestamp=
#
# "ignore" names lines that programs rewrite by themselves (times, window
# sizes ...): FILE:BEGINNING. When two copies of FILE are compared, lines
# that start with BEGINNING do not count. The file itself is still kept
# and restored whole.
#
# Built-in items live in items/ next to the program. Your own items live
# in the "items" folder next to your config (config/items/). An item of
# yours may not have the same name as a built-in one: to change a built-in
# item, switch it off in the config and make your own under a new name.
#
# Paths:
#   dconf    /a/b/  = a folder and everything below it
#            /a/b/c = one setting          /a/b/c* = settings starting "c"
#   files    ~/x/   = a folder and everything below it,  ~/x = one file
#            * and ? are wildcards that stay inside one folder level
#   exclude  "~/..." leaves files out, "/..." leaves settings out
#
# When two items name overlapping paths, the most specific (longest) one
# wins; your own items win a tie. Settings that no item names fall to the
# catch-all items "other" and "app-settings", so nothing is ever lost.

ITEM_NAMES=()
declare -A ITEM_SRC=()      # builtin | user
declare -A ITEM_FILE=()     # where the .item file is
declare -A ITEM_DESC=() ITEM_DEFAULT=() ITEM_DCONF=() ITEM_FILES=()
declare -A ITEM_EXCLUDE=() ITEM_SYSTEM=() ITEM_SPECIAL=() ITEM_IGNORE=()

# Settings that are never kept, whatever the items say: they identify this
# computer, give away where you are, or belong to the screen size.
NEVER_KEEP_DCONF="/org/x/warpinator/preferences/connect-id
/org/cinnamon/settings-daemon/plugins/color/night-light-last-coordinates
/org/cinnamon/desktop/interface/scaling-factor
/org/gnome/desktop/interface/scaling-factor"

# load_items BUILTIN_DIR [USER_DIR]
#   Reads every NAME.item file, checks it, and fills the ITEM_* arrays.
#   Stops with a list of every problem found.
load_items() {
    local builtin_dir="$1" user_dir="${2:-}" f problems=0
    ITEM_NAMES=() ITEM_SRC=() ITEM_FILE=() ITEM_DESC=() ITEM_DEFAULT=()
    ITEM_DCONF=() ITEM_FILES=() ITEM_EXCLUDE=() ITEM_SYSTEM=() ITEM_SPECIAL=() ITEM_IGNORE=()

    for f in "$builtin_dir"/*.item; do
        [ -f "$f" ] || continue
        load_item_file "$f" builtin || problems=$((problems + 1))
    done
    if [ -n "$user_dir" ] && [ -d "$user_dir" ]; then
        for f in "$user_dir"/*.item; do
            [ -f "$f" ] || continue
            load_item_file "$f" user || problems=$((problems + 1))
        done
    fi
    [ "${#ITEM_NAMES[@]}" -gt 0 ] || die "no items found in $builtin_dir"
    [ "$problems" -eq 0 ] || die "please fix the item file(s) above"
}

# load_item_file FILE SOURCE -> reads one item; returns 1 on any problem.
load_item_file() {
    local file="$1" src="$2" name section key value p bad=0
    name="$(basename "$file" .item)"
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        err "$file: an item name may only use a-z, 0-9 and \"-\""; return 1
    fi
    if [ -n "${ITEM_SRC[$name]+set}" ]; then
        err "$file: an item called \"$name\" already exists (${ITEM_FILE[$name]}); please use another name"
        return 1
    fi
    ITEM_NAMES+=("$name")
    ITEM_SRC[$name]="$src" ITEM_FILE[$name]="$file" ITEM_DEFAULT[$name]="on"
    ITEM_DESC[$name]="" ITEM_DCONF[$name]="" ITEM_FILES[$name]="" ITEM_EXCLUDE[$name]=""
    ITEM_SYSTEM[$name]="" ITEM_SPECIAL[$name]="" ITEM_IGNORE[$name]=""

    while IFS=$'\t' read -r section key value; do
        if [[ "$section" == !* ]]; then err "$file line ${section#!}"; bad=1; continue; fi
        case "$key" in
            description) ITEM_DESC[$name]="$value" ;;
            default)
                case "$value" in on|off) ITEM_DEFAULT[$name]="$value" ;;
                    *) err "$file: default must be on or off"; bad=1 ;; esac ;;
            dconf)   ITEM_DCONF[$name]="$value" ;;
            files)   ITEM_FILES[$name]="$value" ;;
            exclude) ITEM_EXCLUDE[$name]="$value" ;;
            system)  ITEM_SYSTEM[$name]="$value" ;;
            special) ITEM_SPECIAL[$name]="$value" ;;
            ignore)  ITEM_IGNORE[$name]="$value" ;;
            *) err "$file: unknown field \"$key\""; bad=1 ;;
        esac
    done < <(parse_ini "$file" item)

    [ -n "${ITEM_DESC[$name]}" ] || { err "$file: description is missing"; bad=1; }
    while IFS= read -r p; do
        valid_dconf_path "$p" || { err "$file: dconf path \"$p\" is not valid"; bad=1; }
    done < <(split_words "${ITEM_DCONF[$name]}")
    while IFS= read -r p; do
        valid_home_path "$p" || { err "$file: file \"$p\" must start with ~/ (no ..)"; bad=1; }
    done < <(split_words "${ITEM_FILES[$name]}")
    while IFS= read -r p; do
        valid_home_path "$p" || valid_dconf_path "$p" \
            || { err "$file: exclude \"$p\" must start with ~/ (a file) or / (a setting)"; bad=1; }
    done < <(split_words "${ITEM_EXCLUDE[$name]}")
    while IFS= read -r p; do
        [[ "$p" == /* && "$p" != "$HOME"/* && "/$p/" != */../* ]] \
            || { err "$file: system file \"$p\" must be a full path outside your home"; bad=1; }
    done < <(split_words "${ITEM_SYSTEM[$name]}")
    for p in ${ITEM_SPECIAL[$name]}; do
        case "$p" in wallpaper|language|timezone|software|crontab) ;;
            *) err "$file: unknown special \"$p\""; bad=1 ;; esac
    done
    while IFS= read -r p; do
        valid_home_path "${p%%:*}" && [[ "$p" == *:?* ]] \
            || { err "$file: ignore \"$p\" must look like ~/path/file:beginning-of-line"; bad=1; }
    done < <(split_words "${ITEM_IGNORE[$name]}")
    [ "$bad" -eq 0 ]
}

valid_dconf_path() {
    local p="$1" body="${1%\*}"
    [[ "$p" == /* && "$p" != *//* && "$body" != *\** && "$p" != *'/*' ]]
}
valid_home_path() { [[ "$1" == "~/"?* && "/$1/" != */../* ]]; }

# check_config_items -> every name in the config's [items] must exist.
check_config_items() {
    local name problems=0
    for name in "${!CONF_ITEMS[@]}"; do
        if [ -z "${ITEM_SRC[$name]+set}" ]; then
            err "$CONF_FILE: [items] unknown item \"$name\" (see items/ and $(to_tilde "$USER_ITEMS_DIR"))"
            problems=$((problems + 1))
        fi
    done
    [ "$problems" -eq 0 ] || exit 1
}

# item_on NAME -> success if the item is switched on (config, else default).
item_on() {
    local v="${CONF_ITEMS[$1]:-}"
    if [ -n "$v" ]; then [ "$v" = "yes" ]; else [ "${ITEM_DEFAULT[$1]:-off}" = "on" ]; fi
}

# items_on -> the names of all switched-on items, one per line.
items_on() {
    local n
    for n in "${ITEM_NAMES[@]}"; do item_on "$n" && printf '%s\n' "$n"; done
    return 0
}

# item_has NAME SPECIAL -> success if the item has that special source.
item_has() { [[ " ${ITEM_SPECIAL[$1]:-} " == *" $2 "* ]]; }

# is_main_item NAME -> built-in and on by default; everything else (your
#   own items, optional items) is "extra" and shown separately in a diff.
is_main_item() { [ "${ITEM_SRC[$1]:-}" = "builtin" ] && [ "${ITEM_DEFAULT[$1]:-}" = "on" ]; }

# items_in_order -> your own items first (they win ties), then built-in.
items_in_order() {
    local n
    for n in "${ITEM_NAMES[@]}"; do [ "${ITEM_SRC[$n]}" = "user" ] && printf '%s\n' "$n"; done
    for n in "${ITEM_NAMES[@]}"; do [ "${ITEM_SRC[$n]}" = "builtin" ] && printf '%s\n' "$n"; done
    return 0
}

# write_dconf_patterns FILE -> "kind<TAB>item<TAB>path" lines for dconf.awk.
#   kind: inc (the item takes it), exc (the item leaves it out),
#   never (nobody keeps it). ALL items are listed, also switched-off ones,
#   so a switched-off item's settings are not swallowed by a catch-all.
write_dconf_patterns() {
    local out="$1" n p
    : > "$out"
    while IFS= read -r n; do
        while IFS= read -r p; do printf 'inc\t%s\t%s\n' "$n" "$p" >> "$out"; done < <(split_words "${ITEM_DCONF[$n]}")
        while IFS= read -r p; do
            [[ "$p" == /* ]] && printf 'exc\t%s\t%s\n' "$n" "$p" >> "$out"
        done < <(split_words "${ITEM_EXCLUDE[$n]}")
    done < <(items_in_order)
    while IFS= read -r p; do printf 'never\t-\t%s\n' "$p" >> "$out"; done <<< "$NEVER_KEEP_DCONF"
}

# write_file_patterns FILE -> "kind<TAB>item<TAB>/full/path" for files.awk.
write_file_patterns() {
    local out="$1" n p
    : > "$out"
    while IFS= read -r n; do
        while IFS= read -r p; do printf 'inc\t%s\t%s\n' "$n" "$(expand_home "$p")" >> "$out"; done < <(split_words "${ITEM_FILES[$n]}")
        while IFS= read -r p; do
            [[ "$p" == "~/"* ]] && printf 'exc\t%s\t%s\n' "$n" "$(expand_home "$p")" >> "$out"
        done < <(split_words "${ITEM_EXCLUDE[$n]}")
    done < <(items_in_order)
    return 0
}
