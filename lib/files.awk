# lib/files.awk -- decide which item each file belongs to.
#
# Input 1: patterns, "kind<TAB>item<TAB>/full/path" (see write_file_patterns)
# Input 2: full paths of files found on disk, one per line
#
# Output: "item<TAB>path" for every file that belongs to an item and is
# not excluded by it. The longest matching pattern wins; on a tie, the
# earlier line wins.
#
# Patterns: a folder ends with "/" and covers everything below it.
# "*" and "?" are wildcards that never cross a "/".
#
# Example: with these two patterns
#     inc  appearance  /home/alex/.config/gtk-3.0/
#     inc  nemo        /home/alex/.config/gtk-3.0/bookmarks
# the file .../gtk-3.0/bookmarks belongs to "nemo" (the longer pattern)
# and .../gtk-3.0/settings.ini to "appearance".

BEGIN { FS = "\t" }

FNR == NR {
    np++
    kind[np] = $1; item[np] = $2; len[np] = length($3); re[np] = to_regex($3)
    next
}

$0 != "" {
    path = $0; owner = ""; blen = -1
    for (i = 1; i <= np; i++)
        if (kind[i] == "inc" && len[i] > blen && path ~ re[i]) { owner = item[i]; blen = len[i] }
    if (owner == "") next
    for (i = 1; i <= np; i++)
        if (kind[i] == "exc" && item[i] == owner && path ~ re[i]) next
    print owner "\t" path
}

# to_regex(PATTERN) -> a regular expression for a path pattern.
function to_regex(p,    i, c, out, folder) {
    folder = (p ~ /\/$/)
    out = "^"
    for (i = 1; i <= length(p); i++) {
        c = substr(p, i, 1)
        if (c == "*")      out = out "[^/]*"
        else if (c == "?") out = out "[^/]"
        else if (index("\\.^$+(){}[]|", c) > 0) out = out "\\" c
        else out = out c
    }
    return folder ? out : out "$"
}
