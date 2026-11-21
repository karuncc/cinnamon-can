#!/usr/bin/env bash
#
# test/15-can-contents.sh -- what a can must never hold.
#
# Part of the tests: "bash test/run-tests.sh" runs every file; this one
# also runs on its own: "bash test/15-can-contents.sh".

source "$(dirname "$0")/lib.sh"

section "What a can must NOT hold (hardware and personal are off)"
use_base_can
U="$TMP/unpack-clean"; mkdir "$U"; tar -C "$U" -xzf "$BASE"
check "no screen-tied settings (text or pointer size)" \
    sh -c 'cd "$1" && ! grep -qE "text-scaling-factor|cursor-size" items/*/dconf.ini' sh "$U"
check "no update/install history of this machine" \
    sh -c 'cd "$1" && ! grep -qE "install-last-run|refresh-last-run|installed-apps" items/*/dconf.ini' sh "$U"
check "no never-kept settings (connect-id ...)" \
    sh -c 'cd "$1" && ! grep -qE "^(connect-id|night-light-last-coordinates|scaling-factor)=" items/*/dconf.ini' sh "$U"
check "no personal or per-machine files" \
    sh -c '! find "$1/items" -path "*enchant*" -o -name "monitors.xml" -o -path "*Templates*" | grep -q .' sh "$U"

section "The software list: programs you put in /usr/local/bin"
# Only the files no package owns are listed. dpkg is asked once for all
# of them; a stand-in answers that a file whose name has an even number
# of letters belongs to a package, any other does not.
mkdir -p "$TMP/fake-dpkg"
cat > "$TMP/fake-dpkg/dpkg" <<'EOF'
#!/bin/sh
[ "$1" = "-S" ] || exit 1
shift; st=0
for f; do
    n="$(basename "$f")"
    if [ $(( ${#n} % 2 )) -eq 0 ]; then echo "cc-package: $f"
    else echo "dpkg-query: no path found matching pattern $f" >&2; st=1; fi
done
exit $st
EOF
chmod +x "$TMP/fake-dpkg/dpkg"
want=""
for f in /usr/local/bin/*; do
    [ -f "$f" ] || continue
    n="${f##*/}"; [ $(( ${#n} % 2 )) -eq 0 ] || want+="$f"$'\n'
done
if compgen -G '/usr/local/bin/*' >/dev/null; then
    got="$(env PATH="$TMP/fake-dpkg:$PATH" bash -c 'CC_ROOT="$1"
               source "$1/lib/common.sh" >/dev/null; source "$1/lib/items.sh"; source "$1/lib/collect.sh"
               CC_TMP="$2"; write_software_list' sh "$ROOT" "$TMP" | sed -n '/^\[local-programs\]$/,/^\[sources\]$/p' | sed '1d;$d')"
    check "only the programs no package owns are listed" [ "$got" = "${want%$'\n'}" ]
else
    skip "this computer has nothing in /usr/local/bin"
fi

finish
