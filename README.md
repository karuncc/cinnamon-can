# cinnamon-can

Keep your **Linux Mint Cinnamon** desktop in cans, and open a can to get it
back — on this computer or on a new one.

```
cinnamon-can seal -L "Before upgrade"   # put the current desktop in a new can
cinnamon-can list                       # all cans, with their IDs
cinnamon-can peek K7Q2                  # what is inside can K7Q2
cinnamon-can diff K7Q2                  # what would change
cinnamon-can open K7Q2                  # make this computer match it
```

It is plain `bash` and `awk` and uses only tools that come with Mint.
Nothing to install.

---

## Scope and limitations — read this first

**Goal.** After `open` on another computer, the desktop looks, is arranged
and feels the same: themes, fonts, panels and the order of their icons,
menu, every keyboard shortcut, mouse and keyboard speeds, languages ...
Things that depend on which apps are installed can only match once those
apps are installed (cinnamon-can tells you which ones are missing).

**Supported:** Linux Mint 22.x, Cinnamon edition, X11 session, run as your
normal user. Cans move best between computers with the **same Mint
release and Cinnamon version**: settings are stored as "what you changed
from the defaults", and the defaults are only identical within one version.
Every comparison warns you when the versions differ.

**Not supported:** other desktops or distributions, Wayland (it warns),
running as root (only `open` may be run with sudo, see below).

**Not what it is:**
- not a full backup — use Timeshift for the system and a backup tool for
  your documents;
- not an installer — it lists the apps you installed and shows the commands
  to install the missing ones, but never runs them;
- **not encrypted** — a can holds your settings and some files in plain
  form. Keep cans somewhere private. Never add keys or passwords to an item;
- not a polished product — a small tool that grew out of one desktop,
  written and maintained mostly with an AI assistant, and tested by
  running it there. It is shared as it is: issues are read, but nothing
  is promised.

---

## Getting started

Get the code once, anywhere you like (the examples use `~/repos`), and
create your config from the example:

```
git clone https://github.com/karuncc/cinnamon-can ~/repos/cinnamon-can
cd ~/repos/cinnamon-can
cp config/example.conf config/default.conf
```

The tool does not run without a config. Edit it if you like (everything is
explained inside). To use the command from anywhere:

```
mkdir -p ~/.local/bin
ln -s "$PWD/cinnamon-can" ~/.local/bin/cinnamon-can
```

To remove cinnamon-can later, delete that link and this folder — and the
backup folder `~/cinnamon-cans` only if you no longer need your cans.

---

## How to use it

### Make a can

```
cinnamon-can seal
cinnamon-can seal -L "Before upgrade"    # or --label="Before upgrade"
```

```
   INFO  Reading this computer's settings ...

   INFO  Sealing the can [K7Q2] ...
         └ Label: Before upgrade
         └ When:  2026-11-13 14:30:00 +07:00
         └ On:    mylaptop (Linux Mint 22.3, Cinnamon 6.6.9, x86_64)

   INFO  Items to be sealed:
         • ITEM             SETTINGS  FILES EXTRAS
         └ appearance             37      4 wallpaper mountains.png
         └ keyboard               64     16
         └ language                0      0 language en_US, formats en_US.UTF-8
         └ software                0      0 12 apps, 13 language packages, 1 flatpak
         └ system                  0      3 time zone Europe/Berlin
         └ • my-scripts            1      3

   INFO  Software, themes and fonts the can uses:
         └ All installed on this computer

     OK  The can is sealed:
         └ ID:     [K7Q2]
         └ Size:   410.4 KB
         └ Folder: ~/cinnamon-cans
         └ File:   manual-K7Q2-20261113T143000+0700.tar.gz.canned
```

It prints the can's **ID** (four characters, e.g. `K7Q2`), what each item
holds, and what the can uses that this computer has not installed (for
example an app that is pinned to the panel but no longer installed). A
`•` before an item's name (blue in a terminal) marks one of your own
items (see "Your own items"); the grey `•` that starts a table's heading
row is only the point its rows hang from.

### Find a can

```
cinnamon-can list
```

```
   INFO  Cans stored in ~/cinnamon-cans:
         • ID     KIND    CREATED          HOST         MINT / CINN.       SIZE LABEL
 Latest: └ [R4T8] autocan 2026-11-13 15:05 mylaptop     22.3 / 6.6.9   402.1 KB Before opening K7Q2
         └ [K7Q2] manual  2026-11-13 14:30 mylaptop     22.3 / 6.6.9   410.4 KB Before upgrade

   INFO  Latest applied on this computer: can [K7Q2]
         └ 2026-11-13T15:05, system files restored
```

`manual` cans are the ones you made (blue in a terminal). An `autocan` is
made by `open` just before it changes anything — it is your undo. The
newest can comes first, marked `Latest:`. IDs can be typed in lower case.
Wherever a command takes a CAN you may also give the path of a can file.

### Look inside a can

```
cinnamon-can peek K7Q2
```

Shows when and on which computer and versions the can was made, the same
table of items as `seal`, and the list of software you had installed
(`(none)` where a kind is empty). It shows only the can: what differs
from this computer (other versions, and what the can uses that is not
installed here) is shown by `diff`.

### Compare

```
cinnamon-can diff K7Q2          # this computer (-) against the can (+)
cinnamon-can diff K7Q2 R4T8     # can K7Q2 (-) against can R4T8 (+)
```

```
   INFO  Reading this computer's settings ...
   INFO  Comparing:
         (-) This computer
         (+) Can [K7Q2] (Label: Before upgrade)

         keyboard
         └ /org/cinnamon/desktop/keybindings/wm/close
 -         ['<Alt>F4']
 +         ['<Super>q']
         └ /org/cinnamon/desktop/peripherals/keyboard/repeat-interval
 -         uint32 30
 +         (default)

         panel
         └ • ~/.config/cinnamon/spices/calendar@cinnamon.org/13.json  (+1 | -1)
      10           "tooltip": "Check this to display events in the calendar.",
 -    11           "value": true
 +    11           "value": false
      12       },
   [NEW] └ • ~/.config/cinnamon/spices/calendar@cinnamon.org/99.json  (+3 | -0)

         system
         └ • /etc/default/locale [SUDO REQUIRED]  (+1 | -1)
 -     1   LANG=en_US.UTF-8
 +     1   LANG=th_TH.UTF-8

         hardware (optional item)
         └ /org/cinnamon/desktop/interface/text-scaling-factor
 -         1.0
 +         1.25

   WARN  Software, themes and fonts the can uses, not installed here:
         • TYPE      NAME                                 USED BY ITEM
         └ apt       code                                 software
         └ apt       gimp                                 software

         To install the missing software, check the list above, then run:
       $ sudo apt install code gimp

   INFO  Summary of the comparison above:
         └ ● 3 setting(s) differ
         └ ● 2 file(s) differ
         └ ● 1 system change(s) differ (only with sudo)
         └ ● 2 thing(s) used by the can but not installed here (listed above)
```

How to read it:
- `(-)` is this computer (or the first can), `(+)` is the can that would
  be opened. Every changed line starts with `-` or `+` on the left (a red
  or green block in a terminal).
- Each item is a heading. Under it, `└ /...` is a setting and `└ • ~/...`
  a file, with `(+N | -N)`: how many lines the can adds and removes. The
  grey numbers next to the `-`/`+` are line numbers in the file.
- `(default)` means the setting is at Cinnamon's default on that side.
- `[NEW]` / `[DEL]`: files only one side has. Against this computer,
  `[NEW]` is a file `open` would create and `[DEL]` one it would delete
  (never a system file); between two cans, `[NEW]` is only in the second
  and `[DEL]` only in the first. This is normal — for example a theme you
  installed, or an applet only one panel has.
- Changed **values** are normal. A changed **shape** (a setting name or a
  file's structure that looks different) usually means the two sides run
  different Cinnamon versions.
- Optional items and your own items come last, marked `(optional item)`
  or `(your own item)`; your own items also have a blue `•` before their
  name wherever an item is named.
- Two cans are compared item by item as the `+` can sorts things, so a
  setting or file that one can keeps in an item of your own and the other
  in a built-in item is not shown twice. A file of the `-` can that no
  item of the `+` can takes cannot be compared: a warning on top says how
  many there are, and how to see them.
- `[SUDO REQUIRED]` marks system files and the time zone: they are only
  put back with sudo (below).
- What programs write by themselves (where a window was, a time stamp) is
  not shown: built-in items `ignore` it, and you can add more (see "Your
  own items").
- "Software, themes and fonts the can uses" is always shown: `All
  installed on this computer`, or a warning that lists the themes, fonts,
  apps and packages the can names but this computer lacks, with the item
  that uses each one (the item whose settings or files name it). They are
  never installed for you.
- The dots of the summary: green when nothing differs, yellow when
  something does (system changes too), red for what is missing here.

`diff`, `open` and `list` show long output page by page with `less`; set
`PAGER` to use another program.

### Open a can

```
cinnamon-can open K7Q2
```

1. Shows the same comparison as `diff`, with a warning on top if the can
   comes from another Mint or Cinnamon version.
2. Asks you to type `yes`. Anything else, or Ctrl+C, changes nothing.
3. Saves the current state as an `autocan` (your undo).
4. Makes this computer match the can: files first, then settings and your
   language. If fcitx is running, it is asked to reload, so it does not
   write its old settings back (ibus keeps its settings among the others
   and needs nothing more). Files the can does not have are removed (they
   were shown as `[DEL]`). The old home folder
   (`/home/olduser/...`) is replaced by yours everywhere. A wallpaper image
   this computer does not have is copied to
   `~/.local/share/backgrounds/cinnamon-can/`. Each step shows `[DONE]`,
   or `[FAIL]` with the reason under it. Ctrl+C is off while this runs (a
   few seconds), so the computer is never left half done.
5. Prints how to undo (under an `UNDO` badge), writes the log, and asks
   whether to **restart the computer** now: the desktop shows some
   changes only after a restart. Type `yes` to restart; anything else, or
   Ctrl+C, leaves it to you (logging out and in is enough for most
   changes).

```
   INFO  Applying changes from the can [K7Q2] to this computer ...
         Ctrl+C is off until this is done
         └ • Files            [DONE]
         └ • Settings         [DONE]
         └ • Language         [DONE]

     OK  This computer's settings now match the can [K7Q2]

   UNDO  To go back to how this computer was, run:
       $ cinnamon-can open R4T8

   INFO  The desktop shows some changes only after a restart.
         Type "yes" to restart now: no
   WARN  Not restarted.
         Please restart (or log out and in) yourself soon. To restart, run:
       $ systemctl reboot
```

**System files** (login screen, system language and keyboard, time zone)
need admin rights. A normal `open` leaves them and tells you so; to include
them run:

```
sudo ~/repos/cinnamon-can/cinnamon-can open K7Q2
```

Give sudo the full path: it does not look in `~/.local/bin`. (When system
files differ, `open` prints this command with the right path for you.)
Even then the tool works as you; sudo is used only to write those files.
System files are never deleted.

**Undo:** `cinnamon-can open <the autocan's ID>` — shown at the end of every
`open`, and found in `list` / the log.

---

## What is kept

Every part is an **item**: one small file in `items/` saying what it keeps.

| Item | Keeps | Default |
|---|---|---|
| `appearance` | themes, icons, pointer, fonts and font rendering, wallpaper (with the image), GTK look | on |
| `panel` | panels, applets and their settings (e.g. the sound applet's album art), desklets, extensions, hot corners | on |
| `desktop` | desktop icons and their positions | on |
| `menu` | menu layout, favourites, your own launchers | on |
| `keyboard` | layouts, **all shortcuts**, repeat speed, input method (fcitx, ibus) | on |
| `mouse-touchpad` | double-click, pointer speed, scrolling, touchpad, gestures | on |
| `windows` | window behaviour, title bar buttons, workspaces, Alt-Tab, effects | on |
| `sound` | sound effects, alert sounds, your own sound themes | on |
| `power` | power management, screen blanking, lock screen | on |
| `default-apps` | preferred apps, terminal, startup apps, user folders | on |
| `nemo` | file manager preferences, bookmarks, actions, scripts | on |
| `language` | display language and formats of your account | on |
| `system` | login screen, system language and keyboard, time zone (sudo) | on |
| `software` | list of apps you installed: apt (top-level only), Flatpak, `/usr/local/bin`, extra sources | on |
| `other` | every remaining desktop setting (date & time, notifications, accessibility ...) | on |
| `app-settings` | settings apps keep in the settings database (Text Editor, Terminal ...) | on |
| `shell` | `.bashrc`, `.profile`, `~/.local/bin`, user services, crontab | off |
| `dev-tools` | `.gitconfig`, `.vimrc`, `.nanorc`, VS Code settings | off |
| `personal` | account picture, desktop launchers, your dictionary words, document templates | off |
| `hardware` | monitor layout, text and pointer size, colour profiles, audio device names (same model only) | off |

**Never kept:** Warpinator's computer ID, the night-light location, the
screen scaling factor, when the Update Manager last ran and which apps
the Mint installer put on, and private histories: what you typed into
the Run dialog (Alt+F2) and Looking Glass, what you searched for in Text
Editor and in Passwords and Keys, the Bluetooth devices you connected to,
and the PGP key you last signed with. What no item looks at all (Wi-Fi,
printers, keys ...) is listed under "Moving to a new computer".

Switch items on or off in `config/default.conf`:

```ini
[items]
language = no
shell    = yes
```

### Your own items

Put a file in `config/items/`, for example `config/items/my-scripts.item`:

```ini
description = My scripts folder and text editor settings
default     = on
dconf       = /org/x/editor/
files       = ~/Scripts/
exclude     = ~/Scripts/tmp/
```

- `dconf`: `/a/b/` a folder of settings, `/a/b/c` one setting, `/a/b/c*`
  settings whose name starts with `c`. See them with `dconf dump /`.
- `files`: `~/x/` a folder, `~/x` one file; `*` and `?` match within one
  folder.
- `exclude`: `~/...` files or `/...` settings to leave out. They are not
  kept at all: use it for what is private or only means something on this
  computer.
- `ignore`: what a program writes by itself — where a window was, which
  version ran last, a time stamp. It is still kept and restored with the
  rest of the item, but it does not count as a difference, so it never
  shows up in `diff` on its own. Settings are written as in `dconf`, or
  as a name in any folder of the item: `*/window-size`, `*/migrated*`
  (starts with), `*/*-history` (ends with). Lines in a file are written
  `~/path/file:start-of-line`. Example:

  ```ini
  ignore = /org/x/editor/state/  */window-size
           ~/.config/nemo/desktop-metadata:nemo-icon-view-layout-timestamp=
  ```
- `system`: system files, as full paths outside your home (`/etc/...`).
  Like those of the built-in `system` item, they are only put back by
  `sudo ... open`, and never deleted.
- `special`: what is neither a setting nor a file — `wallpaper` (with
  the image), `language`, `timezone`, `software` (the list of apps) or
  `crontab`. The built-in items show how each is used.

Your items have a blue `•` before their name in `seal`, `peek` and
`diff` (in `diff` also the note `(your own item)`), so you can tell them
from the built-in ones.

When `diff` keeps showing a line you did not change, a program wrote it
by itself: add it to your item's `ignore`. If it comes from a built-in
item, please open an issue (or see "Ignore lines in built-in items" in
`CONTRIBUTING.md`), so everyone gets the fix. Your `diff` always uses the
`ignore` lines of the items on this computer as well as the can's own,
so a line added today also quiets cans you sealed before.

Your item may not use the name of a built-in one. To change a built-in
item, switch it off and make your own under a new name (copying the
built-in file is a good start).

---

## Moving to a new computer

1. Update both computers until they run the same Mint release and the same
   Cinnamon version (`cinnamon --version`).
2. Old computer: `cinnamon-can seal -L "Move"`, then copy the can (from
   `~/cinnamon-cans/`) to the new computer's `~/cinnamon-cans/`.
3. New computer: get cinnamon-can, create the config, then
   `cinnamon-can diff ID` and install what it lists as not installed (apps,
   fonts, themes) — their settings then apply right away.
4. `cinnamon-can open ID` — with sudo and the full path (see "Open a can")
   to include the system files. Type `yes` when it asks to restart.
5. Things cinnamon-can does not handle: printers, Wi-Fi and VPN
   connections (with their passwords), Bluetooth pairing, online accounts,
   browser data, SSH/GPG keys, user groups, firewall, drivers. A Web
   App's launcher comes along, but its browser profile does not (it holds
   logins): make the Web App again on the new computer.

## Configuration

`config/default.conf` (see `config/example.conf`):

```ini
[general]
backup_dir = ~/cinnamon-cans

[items]
# name = yes | no
```

Several configs can live side by side: `cinnamon-can -c laptop seal` uses
`config/laptop.conf`; `-c` (or `--config-file`) also takes a full path.

## Command line

```
cinnamon-can [-c CONFIG] COMMAND
cinnamon-can -v | --version        the version
cinnamon-can -h | --help | help    the list of commands
```

Exit codes: `0` when all went well (for `diff`: no differences), `1` when
something failed, `diff` found differences, or you did not confirm `open`;
`2` for an unknown command; `130` when you stopped it with Ctrl+C (it
says what that left behind). The restart question at the end of `open`
does not change its code, whatever you answer: Ctrl+C there counts as
"no".

## Inside a can

A can is a `.tar.gz` file with this inside:

| Path | Contents |
|---|---|
| `manifest.txt` | ID, kind, label, time, computer, versions, home folder, items (an autocan also names the can it was saved before) |
| `catalog/` | every item file known when the can was made (`builtin/`, and `user/` for your own) |
| `items/ITEM/dconf.ini` | the item's settings, in `dconf dump` format |
| `items/ITEM/home/...` | the item's files, as found in your home folder |
| `items/ITEM/root/...` | system files (e.g. `root/etc/default/locale`) |
| `items/ITEM/wallpaper/` | the wallpaper image |
| `items/ITEM/*.txt` | wallpaper name, language, time zone, software list, crontab |

The log, `~/cinnamon-cans/cinnamon-can.log`, records every `seal` and `open`.

## Contributing

Branch, commit, pull request and release conventions are in
`CONTRIBUTING.md`, and the working rules (for people and AI tools alike)
in `AGENTS.md`. Each release is summed up in its notes on the GitHub
Releases page. Run `bash test/run-tests.sh` after a change.

## License

cinnamon-can is released under the MIT License (see `LICENSE`): use it,
change it and share it freely. It comes without any warranty — read the
diff before you type `yes`.
