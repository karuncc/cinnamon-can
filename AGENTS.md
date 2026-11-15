# AGENTS.md — working on cinnamon-can

(`CLAUDE.md` is a link to this file: every tool reads the same rules.)

## What this is

A small command-line tool that keeps a Linux Mint Cinnamon desktop in
"cans" (snapshots) and puts it back:

- `seal [-L TEXT]` makes a can, `list` shows cans, `peek CAN` shows what is
  inside, `diff CAN [CAN2]` compares, `open CAN` makes the computer match a
  can (shows the diff, asks for `yes`, saves an "autocan" first, then
  restarts the computer).
- Goal: after `open` on another computer, the desktop looks, is arranged
  and feels (mouse, keyboard) exactly the same, except for apps that are
  installed differently. Personal things and pure hardware (screens,
  volume, device names) are left out unless an optional item asks for them.

## Hard rules

- **bash + POSIX awk only.** Mint ships `mawk`: no gawk-only features
  (`gensub`, `asort`, `IGNORECASE`, `@include` ...). Only tools present on
  a fresh Mint install. No Python, Node or anything to install.
- Everything in the repo is **English**: code, comments, output, docs.
  Comments are written for readers who are **not programmers**.
- `set -euo pipefail` is on: a pipeline whose first part can fail (e.g.
  `find` on a missing folder) needs `|| true`, or the program stops
  silently.
- Two bash traps that have already bitten this project: with `set -e`, an
  assignment `x="$(command)"` stops the whole program when the command
  fails (add `|| true` when that is not meant); and `IFS=$'\t' read`
  treats tab characters next to each other as ONE separator, so an empty
  middle column shifts all later columns (write a placeholder such as
  `(default)` instead of leaving a column empty).
- sudo is only used by `sudo cinnamon-can open CAN`. The program then
  re-runs itself as the real user (`CC_SYSTEM_RESTORE=1`) and calls `sudo`
  only to write system files. Never run anything else as root.
- No junk files: temporary data goes into `make_tmpdir` (removed on exit);
  cans are written as `.part` and renamed when complete.
- Never put the owner's machine names, user name or hardware model in repo
  files; use generic examples (`mylaptop`, `alex`). The copyright line in
  `LICENSE` is the one agreed exception.

## Layout

```
cinnamon-can          command line, sudo hand-over, dispatch to lib/
items/*.item          built-in items (one file per item)
lib/common.sh         screen layout and messages, temp folder, INI
                      reading, config, system facts, can IDs and lookup,
                      log, utilities
lib/items.sh          reads item files, item_on, patterns for the awk
                      files, the ignore rules
lib/dconf.awk         sorts dconf settings into items (longest path wins)
lib/files.awk         sorts home files into items (longest path wins)
lib/collect.sh        reads this computer into a tree (shared by all)
lib/refs.sh           finds what a can uses that is not installed here,
                      and which item uses it
lib/list.sh           list, peek, reading cans and manifests
lib/diff.sh           views, comparison, the diff report
lib/seal.sh           seal, package_can
lib/open.sh           open: confirm, autocan, apply, log, restart
test/run-tests.sh     the test script (safe to run on this computer)
config/example.conf   the documented example config (the only tracked one)
README.md             the user guide
AGENTS.md             these rules (CLAUDE.md is a link to it)
CONTRIBUTING.md       branches, commit messages, pull requests, releases
LICENSE               MIT
```

## Formats

- **Item file** `NAME.item` (no sections): `description`, `default`
  (on|off), `dconf`, `files`, `exclude`, `system`, `special`
  (wallpaper|language|timezone|software|crontab) and `ignore` (settings
  as in `dconf`, plus `*/name`, `*/name*`, `*/*name` for a setting name in
  any folder of the item, and `~/file:start-of-line` for lines in a file:
  kept and restored with the item, but never counted when comparing).
  Indented lines continue a value; `  #` starts a comment. User items
  live in `items/` next to the config and may not reuse a built-in name.
- **Noise** (what a program or the system writes by itself: window
  places, versions, history, time stamps) goes into the `ignore` of the
  item that takes it; the catch-alls `other` and `app-settings` carry the
  common naming patterns. What is private or only means something on this
  computer (a command history, a computer ID) is not noise: `exclude` it
  (or, across all items, `NEVER_KEEP_DCONF` in `lib/items.sh`). `diff`
  and `open` use the `ignore` of the can's items AND of this computer's
  items of the same name, so a new line also quiets older cans. What may
  go into a built-in `ignore`: "Ignore lines in built-in items" in
  `CONTRIBUTING.md`.
- **Config** `config/default.conf`: `[general] backup_dir`, `[items] name =
  yes|no`. Required; created from `config/example.conf`.
- **Can** `{manual|autocan}-ID-YYYYMMDDTHHMMSS±HHMM.tar.gz.canned`, ID = 4
  characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ`, unique. Inside:
  `manifest.txt`, `catalog/{builtin,user}/*.item` (every item file known
  at seal time), `items/ITEM/{dconf.ini,home/,root/,wallpaper/,
  wallpaper.txt,language.txt,timezone.txt,software.txt,crontab.txt}`.
- **Log** `backup_dir/cinnamon-can.log`: seal and open only, `key=value`.
- Ownership: the longest matching path of ALL items (also switched-off
  ones) wins, user items win ties; catch-alls `other` and `app-settings`.
  `diff` and `open` always split both sides with the **can's** catalog
  (of two cans, the "+" can's: `resplit_tree` in `lib/diff.sh`; a file
  of the "-" can that none of its items takes is not compared, and a
  warning in the report says so).

## Screen output

Every command prints in the same layout (helpers in `lib/common.sh`):

- Two columns: a 9-character left column for a status badge (`info`,
  `ok`, `warn`, `err`) or a mark (`-`/`+`, `[NEW]`/`[DEL]`, and `UNDO` for
  the way back at the end of `open`), and the right column for everything
  else (`say`). Without a terminal the badges are the same words in the
  same places, without colour.
- Blocks of colour are for badges and the `-`/`+` of changed lines; a
  status inside a row is a coloured word in brackets (`[NEW]`, `[DONE]`,
  `[FAIL]`, `[SUDO REQUIRED]`). Only the terminal's own colours (codes
  30-37, 40-47, 90-97, 100-107), never 256-colour codes, so everything
  follows the user's palette.
- Blue marks what the user made: a blue `•` before the name of a user
  item wherever an item is named (`item_dot`, and `item_cell` for a table
  column, both in `lib/items.sh`), and `manual` in the list of cans.
- A line that belongs to the line above starts with a grey `└` (`SUB`,
  `SUB2`); a file name with lines under it gets a yellow `•`
  (`file_dot`). A table is a message, a grey heading row (`table_head`;
  it starts with a grey `•`, the point its rows hang from) and rows that
  start with `└` (`ROW`).
- Ctrl+C always ends on a new line that says what it left behind
  (`on_ctrl_c`: "Cancelled; nothing was changed."). A command sets
  `CC_CANCEL_NOTE` when stopping means more than that (`seal`), and
  switches Ctrl+C off (`trap '' INT`) while it writes something that must
  not be left half done (`open`).
- A command for the user to type is a message line that starts with
  `$ `: it gets a grey `$` in the left column and can be copied as it is.
  Can IDs go through `show_id` (grey block, or `[ID]`), but never inside
  such a command.
- Sentences start with a capital letter, labels the program writes too.
- `warn` and `err` go to stderr; a warning that is part of a report
  (`diff`, `seal`, `list`) uses `msg_lines "$B_WARN"` on stdout, so it
  stays in its place on the page.

## Testing

- After every change, run the test script (it starts with `bash -n` on
  every script):

      bash test/run-tests.sh

  It needs no set-up, writes only into its own temporary folder, and
  never touches the real backup folder or any setting: `open` is only
  exercised in the two cases where it stops by itself, with closed input
  and a fake `systemctl` first in PATH. A few tests compare a can against
  the LIVE computer and can fail when a setting changes mid-run — run the
  script again before hunting for a bug. New behaviour should come with a
  new check in this script.
- The script cannot find noise: it seals and compares within seconds,
  before anything has had time to change by itself. Before a release, also
  check over time: `seal`, use the computer normally for a day (move and
  resize windows, switch the input language, open the usual apps), then
  `diff` that can. Every line the owner did not change is noise (see
  Formats). `dconf dump` only shows settings that were written at least
  once, so also look through the schemas of the installed apps
  (`/usr/share/glib-2.0/schemas/`) for window sizes, "last", "recent" and
  "history".
- NOT covered by the script: really applying a can (`open` + `yes`),
  sudo, language, system files and the restart. For those, the rules
  below apply.
- On the development machine run only `seal`, `list`, `peek`, `diff`, and
  `open` on a can that already matches (it stops before asking). **Never
  answer `yes` to `open` on the real machine** unless the owner asks for it;
  then seal a safety can first, put a `systemctl` shim in `PATH` so the
  machine does not restart under you, and end on the safety can.
- `sudo` does not search `~/.local/bin`: messages and docs must show the
  full path of the program for `sudo ... open`.
- Real writes are tested in a sandbox: `dbus-run-session` with a fake
  `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_RUNTIME_DIR`, `PAGER=cat`
  and shims in `PATH` for `systemctl` (no reboot), `busctl call` (no
  language change), `crontab`, `fcitx-remote` and `sudo`. Use `script` to
  give `open` a terminal. Language, system files and the restart can only
  be tested on the real machine, and only with the owner's permission
  (writing the values that are already there).

## Git

Commit, branch or push only when the person you are working with asks
for it — in the owner's own checkout that means never: the owner makes
every commit, and you propose the branch name, the commit message, the
pull request title and description and, for a release, its notes. The
owner works in the GitHub web page: give each of these as its own
ready-to-paste block, and describe GitHub steps as clicks, not commands.
Whoever types it, person or AI, every branch, commit, pull request and
release follows `CONTRIBUTING.md` in this folder; nothing outside the
repo is needed. Changes reach this repository as pull requests under the
same rules.

Before proposing a commit message, read the repository's actual state
(`git status`, `git diff`, the current branch) and describe what really
changed — not what you remember changing. When the changes mix unrelated
work, propose splitting them into separate commits.
