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
  or a computer ID must not be kept at all: that is `exclude`, not
  `ignore`.

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
  used) as the very last line, after a blank line. Otherwise no trailer.

Example:

```
fix: retry the export when `rsync` drops the connection

- wait up to 5 minutes before giving up, since the job starts right after wake
- log each retry to `logs/export.log`

Assisted-by: Claude Fable 5
```

## Pull requests

- Fork, make a `type/short-kebab-name` branch, and keep every commit in
  the format above — AI-written commits included; that is what the
  `Assisted-by` trailer is for.
- Run `bash test/run-tests.sh` before opening the pull request; it must
  end with `0 failed`, and new behaviour comes with a new check.
- The title follows the summary rules above; the description says what
  changed and why, in a few short bullets.
- Pull requests are merged on GitHub as a merge commit or a squash —
  never a rebase.

## Releases

Releases are made on GitHub's Release page, not on the command line:

1. Bump `CC_VERSION` at the top of `cinnamon-can` in a
   `chore: release X.Y.Z` commit.
2. On GitHub, create a release with a new `vX.Y.Z` tag. The release
   notes are the changelog: a few bullets in the same style as a commit
   body, saying what the release changes at an overview level.
