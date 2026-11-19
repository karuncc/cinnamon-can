# Contributing to cinnamon-can

Everything needed to work on this project is inside this folder: the
working rules in `AGENTS.md`, the tests in `test/`, and the conventions
below. Nothing depends on files outside the repo. The rules apply to
every change, whether a person or an AI tool wrote it — AI tools pick
them up from `AGENTS.md` (`CLAUDE.md` is a link to it), so a change made
with AI help should come out in the same shape by itself.

## Before changing anything

Read `AGENTS.md`. The short version of its hard rules: plain `bash` +
POSIX `awk` only (Mint ships `mawk`), everything in English, comments
written so that non-programmers can follow them, no junk files, and
never put a real machine or user name in a repo file.

## Testing

Run the test script after every change:

    bash test/run-tests.sh

It is safe on a normal computer and cleans up after itself (details in
the script's header). New behaviour should come with a new check. The
parts it cannot cover (really applying a can, sudo, the restart) follow
the sandbox rules in `AGENTS.md`.

## Ignore lines in built-in items

Programs write some things by themselves: where a window was, which
version ran last, a time stamp. Built-in items list them under `ignore`,
so they never show up in `diff` as a change (see `AGENTS.md`, Formats).
Every user gets these lines and cannot take one back, so a line goes in
only when:

- **The program is common**: it comes with Linux Mint or many people use
  it. For a rarer program, use your own item.
- **The program really writes it by itself**, the user did not choose
  it: it showed up in the over-time check in `AGENTS.md` (seal, use the
  computer for a day, `diff`), or the program's schema or code shows it
  is a window place, a version, a history or a time stamp.
- **A wide pattern** (`*/name*`, `*/*name`) was checked against the
  schemas of the installed programs (`/usr/share/glib-2.0/schemas/`) and
  catches no setting a user would choose. When in doubt, list full paths.
- **It is not private.** A history of what the user typed, device names
  or a computer ID must not be kept at all: that is `NEVER_KEEP_DCONF`
  in `lib/items.sh`, not `ignore` (see `AGENTS.md`, Formats).

Put the line in the item that takes the setting or file (`diff` shows
each change under its item's name), with a comment saying what writes
it. A commit that only adds such lines is a `fix`.

## Branches

    type/short-kebab-name           e.g. fix/diff-empty-columns

One branch per group of related work, one commit per step. `type` is one
of the commit types below.

## Commit messages

```
type: summary

- bullet
- bullet

Assisted-by: <model name>
```

- **Types:** `feat`, `fix`, `hotfix`, `refactor`, `style`, `docs`, `chore`.
- **Summary:** English, imperative (add, show, skip), starts lower case
  except identifiers, no period at the end.
- **Backticks:** in the summary and the body alike, wrap proper names,
  file names, commands and identifiers in backticks and keep their casing.
- **Body:** optional, omit it for small commits. One blank line after the
  summary. `- ` bullets, no period at the end, one change per bullet.
  Describe how the commit changes the project at an overview level (what
  it can now do, how it now works), not file by file; with many changes,
  group related ones and summarise each group in one bullet. About 3-5
  short bullets. Give a reason with "since" or "so" only when it is not
  obvious.
- **Trailers:** never add `Co-Authored-By`. If an AI wrote most of the
  code in the commit, add `Assisted-by: <model name>` (the model actually
  used) as the very last line, after a blank line — also in a commit
  without a body. Otherwise no trailer.

Example:

```
fix: retry the export when `rsync` drops the connection

- wait up to 5 minutes before giving up, since the job starts right after wake
- log each retry to `logs/export.log`

Assisted-by: Claude Opus 5.5
```

## Pull requests

A pull request is written like one commit message for the whole branch,
so it looks the same whoever opens it, a person or an AI tool.

- Fork, make a `type/short-kebab-name` branch, and keep every commit in
  the format above — AI-written commits included; that is what the
  `Assisted-by` trailer is for.
- Run `bash test/run-tests.sh` before opening the pull request; it must
  end with `0 failed`, and new behaviour comes with a new check.
- **Title:** a commit summary, same rules. When the branch has several
  commits, use the type and summary of the main change (`feat` before
  `fix`).
- **Description:** written like a commit body: short `- ` bullets saying
  what the whole branch changes, at an overview level. When an AI wrote
  most of the branch, end with `Assisted-by: <model name>` after a blank
  line, as in a commit. Nothing else: no headings, checklists or test
  output. For a branch with one commit, using that commit's summary and
  body as the title and description is recommended.
- **Merging:** on GitHub, as a merge commit or a squash — never a
  rebase. A branch with several commits, one per step, is merged with a
  merge commit, so every step stays in the history. Keep the message
  GitHub proposes (for a merge commit "Merge pull request #N from
  owner/branch" with the title below it): it is the same whoever merges.
  Then delete the branch.

Example:

```
Title:
feat: let items ignore settings that programs write themselves

Description:
- accept settings in an item's `ignore` (also `*/name`, `*/name*`,
  `*/*name`); they are kept and restored, but never counted in `diff`
- use this computer's `ignore` lines as well as the can's, so older
  cans are quieted too
- ignore window places, last-used values and version notes in `nemo`,
  `keyboard`, `other` and `app-settings`
- stop keeping private histories (Run dialog, searches, Bluetooth
  devices)

Assisted-by: Claude Opus 5.5
```

## Releases

Releases are made on GitHub's Release page, not on the command line.

**Version number** `MAJOR.MINOR.PATCH`:

- MAJOR goes up when cans or configs made with an older version stop
  working;
- MINOR goes up when the release lets you do something new;
- PATCH goes up when it only fixes things or improves the docs.

**Steps:**

1. Run the over-time noise check (`AGENTS.md`, Testing) and fix what it
   finds first.
2. Bump `CC_VERSION` at the top of `cinnamon-can` in a
   `chore: release X.Y.Z` commit, through a pull request like any change.
3. On GitHub: Releases → "Draft a new release" → choose a tag, type the
   new `vX.Y.Z` and create it on `main` → title `cinnamon-can X.Y.Z` →
   the notes below → "Publish release".

**Release notes** are the changelog, written for users:

- one short sentence that sums up the release;
- a few `- ` bullets in the style of a commit body, saying what users
  can now do or what behaves differently, new things first, then fixes;
- a closing sentence only when users must know or do something (read
  the limits, seal a new can ...);
- no `Assisted-by`: every commit already carries its own.

Example, the first release:

```
Title:
cinnamon-can 1.0.0

Notes:
First release.

- `seal`, `list`, `peek`, `diff` and `open` snapshot a Linux Mint 22.x
  Cinnamon desktop and put it back, on this computer or on a new one
- one small item file per part of the desktop decides what is kept;
  add your own items and switch any item on or off in the config
- `open` shows the full diff first, asks for `yes`, saves an undo
  autocan, then restarts; system files are only written with sudo
- cans carry their own item catalog, the wallpaper image, language,
  time zone and a software list, and `peek`/`diff` tell you what the
  target computer is missing (never installed for you)
- `test/run-tests.sh` runs 64 checks without touching the computer

See `README.md` for scope and limitations — cans are not encrypted.
```
