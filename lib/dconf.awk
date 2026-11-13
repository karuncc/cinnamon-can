# lib/dconf.awk -- sort the settings database into items.
#
# Input 1: patterns, "kind<TAB>item<TAB>path" (see write_dconf_patterns)
# Input 2: a "dconf dump /" (or the dconf.ini files of a can)
#
#   [org/cinnamon/desktop/interface]
#   gtk-theme='Mint-Y-Aqua'
#
# Every setting goes to the item whose "inc" path matches it best (the
# longest path wins; on a tie, the earlier line wins). It is dropped when
# that item excludes it, or when it is on the "never" list.
#
# Two ways to run it:
#   -v outdir=DIR -v want="item1 item2"   write DIR/ITEM.ini for those
#                                         items, in "dconf load" format
#   -v flat=1                             print item<TAB>path<TAB>value
#
# Path kinds:  /a/b/ folder (any depth)   /a/b/c one setting
#              /a/b/c*  settings in /a/b/ whose name starts with "c"

BEGIN {
    FS = "\n"
    n = split(want, w, " ")
    for (i = 1; i <= n; i++) wanted[w[i]] = 1
}

# First file: the patterns.
FNR == NR {
    split($0, f, "\t")
    np++
    kind[np] = f[1]; item[np] = f[2]; p = f[3]
    if (p ~ /\*$/)      { type[np] = "glob"; p = substr(p, 1, length(p) - 1) }
    else if (p ~ /\/$/) { type[np] = "folder" }
    else                { type[np] = "key" }
    pat[np] = p
    next
}

# Second file: the settings.
/^\[.*\]$/ {
    folder = substr($0, 2, length($0) - 2)
    folder = (folder == "/") ? "/" : "/" folder "/"
    next
}
/^[ \t]*$/ { next }
{
    eq = index($0, "=")
    if (eq == 0) next
    path = folder substr($0, 1, eq - 1)

    if (matches("never", "", path)) next
    owner = best(path)
    if (owner == "") owner = "_unclaimed"
    if (matches("exc", owner, path)) next

    if (flat) print owner "\t" path "\t" substr($0, eq + 1)
    else if (owner in wanted) write_line(owner, folder, $0)
}

# hit(I, PATH) -> 1 if pattern I matches PATH.
function hit(i, path,    rest) {
    if (type[i] == "key") return path == pat[i]
    if (index(path, pat[i]) != 1) return 0
    if (type[i] == "glob") { rest = substr(path, length(pat[i]) + 1); return index(rest, "/") == 0 }
    return 1
}

# best(PATH) -> the item with the longest matching "inc" pattern.
function best(path,    i, b, blen) {
    b = ""; blen = -1
    for (i = 1; i <= np; i++)
        if (kind[i] == "inc" && length(pat[i]) > blen && hit(i, path)) { b = item[i]; blen = length(pat[i]) }
    return b
}

# matches(KIND, ITEM, PATH) -> 1 if a KIND pattern (of ITEM, if given) matches.
function matches(k, it, path,    i) {
    for (i = 1; i <= np; i++)
        if (kind[i] == k && (it == "" || item[i] == it) && hit(i, path)) return 1
    return 0
}

# write_line(ITEM, FOLDER, LINE) -> append to ITEM's file, starting a new
#   [section] when the folder changes. ("in" is tested first: just reading
#   last[item] would create it.)
function write_line(it, fol, line,    file, sec) {
    file = outdir "/" it ".ini"
    if (!(it in last) || last[it] != fol) {
        sec = (fol == "/") ? "/" : substr(fol, 2, length(fol) - 2)
        if (it in last) print "" > file
        print "[" sec "]" > file
        last[it] = fol
    }
    print line > file
}
