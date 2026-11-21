# AGENTS.md — working on cinnamon-can

(`CLAUDE.md` is a link to this file: every tool reads the same rules.)

## What this is

A small command-line tool that keeps a Linux Mint Cinnamon desktop in
"cans" (snapshots) and puts it back:

- `seal [-L TEXT]` makes a can, `list` shows cans, `peek CAN [ITEM]` shows
  what is inside (one item in full: every setting and the text of every
  file), `diff CAN [CAN2]` compares, `open CAN` makes the computer match a
  can (shows a summary of the changes, asks for `yes`, saves an "autocan"
  first, then asks whether to restart the computer), `label CAN TEXT`
  gives a can another label, `delete CAN...` deletes cans (asks for `yes`).
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
- Three bash traps that have already bitten this project: with `set -e`,
  an assignment `x="$(command)"` stops the whole program when the command
  fails (add `|| true` when that is not meant); `IFS=$'\t' read` treats
  tab characters next to each other as ONE separator, so an empty middle
  column shifts all later columns (write a placeholder such as
  `(default)` instead of leaving a column empty); and with `pipefail`, a
  pipe into `grep -q` (or `head`) can fail on long input: it stops reading
  at the first match, the command before it is cut off, and the pipe
  counts as failed (search a variable with `[[ $x == *text* ]]` or
  `grep -q ... <<< "$x"` instead).
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
lib/common.sh         loads the three files below; temp folder, system
                      facts and start-up checks, paths and files
lib/screen.sh         screen layout and messages, text from a can,
                      commands to copy, the pager
lib/config.sh         INI reading, the config, the backup folder
lib/cans.sh           can IDs and file names, lookup, labels, the log
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
lib/open.sh           open: summary, confirm, autocan, apply, log, restart
lib/manage.sh         label (swaps only the manifest), delete
test/run-tests.sh     runs the test files at the same time, shows their
                      results in order (safe to run on this computer)
test/lib.sh           what the test files share: temporary folder,
                      stand-ins, checks, the screen layout of results
test/NN-topic.sh      the checks, one file per part of the program
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
  computer (a command history, a computer ID) is not noise: it goes on
  `NEVER_KEEP_DCONF` in `lib/items.sh`, which holds for every item (an
  `exclude` holds only while its item owns the setting: a user item that
  takes the app's folder would keep it). Also `exclude` it in the
  built-in item that takes it, so older versions reading a new can leave
  it alone; `diff` and `open` drop it from older cans that hold it
  (`drop_never_kept`). `diff`
  and `open` use the `ignore` of the can's items AND of this computer's
  items of the same name, so a new line also quiets older cans. What may
  go into a built-in `ignore`: "Ignore lines in built-in items" in
  `CONTRIBUTING.md`.
- **Config** `config/default.conf`: `[general] backup_dir`, `[items] name =
  yes|no`. Required; created from `config/example.conf`. `backup_dir`
  must be `~`, `~/...` or `/...` (`backup_dir_problem`: anything else
  would depend on the folder the command runs in). The backup
  folder goes through `ensure_backup_dir`: made private (700) only when
  the program makes it, an existing one is never changed (cans and the
  log are 600), and `seal`/`open` stop early when it cannot be written.
- **Can** `{manual|autocan}-ID-YYYYMMDDTHHMMSS±HHMM.tar.gz.canned`, ID = 4
  characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ`, unique. Inside:
  `manifest.txt`, `catalog/{builtin,user}/*.item` (every item file known
  at seal time), `items/ITEM/{dconf.ini,home/,root/,wallpaper/,
  wallpaper.txt,language.txt,timezone.txt,software.txt,crontab.txt}`.
  The label is one line of at most `LABEL_MAX` (40) characters, counted
  as letters, not bytes (`clean_label`); a longer one from an older can
  or a hand-edited manifest is cut where it is shown (`short_label`),
  except in `peek`.
- **Log** `backup_dir/cinnamon-can.log`: seal and open only, `key=value`.
  `delete` leaves the log alone: its IDs keep `new_can_id` from reusing
  them, and `list` says when the can applied last is gone.
- **Unreadable** files and folders (you cannot read them, so neither can
  the desktop) are never kept, compared or written: `collect_tree` lists
  them in `UNREADABLE` (`lib/collect.sh`), `seal`, `diff` and `open`
  name them (`show_unreadable`), and `drop_unreadable` takes them out of
  the comparison, so `open` never writes over or deletes what the autocan
  could not copy. `open_can` makes every file of a can readable, so one
  made by hand is still shown and compared.
- Ownership: the longest matching path of ALL items (also switched-off
  ones) wins, user items win ties; catch-alls `other` and `app-settings`.
  `diff` and `open` always split both sides with the **can's** catalog
  (of two cans, the "+" can's: `resplit_tree` in `lib/diff.sh`; a file
  of the "-" can that none of its items takes is not compared, and a
  warning in the report says so).

## Screen output

Every command prints in the same layout (helpers in `lib/screen.sh`):

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
  `CC_CANCEL_NOTE` when stopping means more than that (`seal`, `delete`),
  and switches Ctrl+C off (`trap '' INT`) while it writes something that
  must not be left half done (`open`, and the last step of `label` and
  `delete`).
- A command for the user to type is a message line that starts with
  `$ `: it gets a grey `$` in the left column and can be copied as it is.
  So a path in it goes through `shell_word` (quoted when it has spaces), a
  can through `can_ref` (its ID, or its path when it was opened from
  elsewhere), and `config_option` repeats the `-c` the program was started
  with. Can IDs go through `show_id` (grey block, or `[ID]`), but never
  inside such a command.
- Text that comes from a can never reaches the terminal as it is: a
  control character in it would be an order to the terminal (erase a
  line, change the colour). The fields of a manifest lose them when it is
  read (`read_manifest`) and a new label when it is given (`clean_label`);
  everything else from a can (setting names and values, file names and
  lines, software names) is shown with them written as plain letters,
  `^[` for ESC: `to_visible`/`visible` in bash, `vis()` in awk (put
  `"$CTRL_AWK"` in front of the program). `shell_word` does it too. A
  name from a can is looked up as plain text (`grep -F --`), never as a
  pattern.
- Sentences start with a capital letter, labels the program writes too.
- `warn` and `err` go to stderr; a warning that is part of a report
  (`diff`, `seal`, `list`, the summary of `open`) uses
  `msg_lines "$B_WARN"` on stdout, so it stays in its place on the page.

## Testing

- After every change, run the tests (`01-syntax.sh` runs `bash -n` on
  every script):

      bash test/run-tests.sh

  The command runs every `test/NN-topic.sh` at the same time and shows
  their results in order, in the program's own screen layout; `bash
  test/run-tests.sh pager 14` runs only the files with that word or
  number in their name, and a file also runs on its own (`bash
  test/13-pager.sh`). The files that test with a can of this computer
  all get a copy of one can that the runner seals first. A `[SKIP]` is a
  check this computer cannot try (the can has no software list ...): it
  is counted, never a failure. Ctrl+C stops every file and leaves
  nothing behind.
  The tests need no set-up, each file writes only into a temporary
  folder of its own, and they never touch the real backup folder or any
  setting: `open` only ever gets closed input, so it can never read a
  `yes`, and a fake `systemctl` is first in PATH. What needs odd files
  or folders (files you cannot read, a read-only or FAT backup folder)
  runs the program with a home folder of its own (`HOME` inside that
  temporary folder), and a stand-in `chmod`, `dconf` or pager where the
  real one would not do. `open` stops by itself on a can that already
  matches, on one where only system files differ, and right after its
  summary on one that differs (no terminal to ask in); its restart
  question is tried on its own, with that fake. `delete` gets its
  answers through `script` (which gives it a terminal) and only deletes
  the test's own cans. A few tests compare a can against the LIVE
  computer and can fail when a setting changes mid-run — run the tests
  again before hunting for a bug. New behaviour should come with a new
  check, in the file of its part of the program (or a new
  `NN-topic.sh`: `source "$(dirname "$0")/lib.sh"`, a `section`, the
  checks, `finish`). A file that loads the program's code
  (`lib/common.sh`) does it with `>/dev/null`, so the program's badges
  are plain words even in a terminal, as the checks expect.
- The tests cannot find noise: they seal and compare within seconds,
  before anything has had time to change by itself. Before a release, also
  check over time: `seal`, use the computer normally for a day (move and
  resize windows, switch the input language, open the usual apps), then
  `diff` that can. Every line the owner did not change is noise (see
  Formats). `dconf dump` only shows settings that were written at least
  once, so also look through the schemas of the installed apps
  (`/usr/share/glib-2.0/schemas/`) for window sizes, "last", "recent" and
  "history".
- NOT covered by the tests: really applying a can (`open` + `yes`),
  sudo, language, system files and the restart itself. For those, the rules
  below apply.
- On the development machine run only `seal`, `list`, `peek`, `diff`, and
  `open` on a can that already matches (it stops before asking). **Never
  answer `yes` to `open` on the real machine** unless the owner asks for it;
  then seal a safety can first, put a `systemctl` shim in `PATH` so the
  machine does not restart under you, and end on the safety can.
- Never run `label` or `delete` on the owner's cans: try them with a
  config whose `backup_dir` is a folder of test cans.
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
same rules: branches start from `dev` and their pull requests go into
`dev`; `main` only changes with a release (a pull request from `dev`)
or a hotfix (`CONTRIBUTING.md`, Branches).

Before proposing a commit message, read the repository's actual state
(`git status`, `git diff`, the current branch) and describe what really
changed — not what you remember changing. When the changes mix unrelated
work, propose splitting them into separate commits.
