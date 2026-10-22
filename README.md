# Inlay

Tiling window manager for macOS, written in Swift. The goal is to bring together in a single native app three
things that today are three programs: the window manager, the borders of the active window and a menu bar item
with the workspaces, all with a single config file (`inlay.toml`).

It builds and installs **with the Xcode Command Line Tools alone**: no Xcode, no Apple account.

<p align="center"><img src="docs/images/hero.png" alt="Illustration of a desktop managed by Inlay: four tiled windows (an editor with inlay.toml, a browser, a terminal and a notes app) with the defaults of the shipped config: gaps of 8 points, a border of 4 points around each window, gray for the inactive ones and orange for the focused one, and the workspaces 1 to 6 as chips in the menu bar, with 2 marked as the focused one" width="880"></p>

<sub>About the images of this page: the ones marked **Real render** are drawn by Inlay itself, off screen, with the
same code that draws the menu bar item, the borders and the Settings window (see [Development](#development)); the
ones marked **Real output** are text printed by the scripts and the CLI; and the ones marked **Illustration**,
like the one above and all the animations, are drawings that follow the rules of the layout, not screenshots.</sub>

## Project status

**Version 0.1.0, in its first round of real use.** Inlay is a fork of
[AeroSpace](https://github.com/nikitabobko/AeroSpace) that builds without Xcode, with its own way of placing
new windows (*dwindle*), without the *accordion* layout, with its own menu bar item and with window borders.

| Part | Status | How it is verified |
|---|---|---|
| Build, install and uninstall without Xcode | Done | Clean build from scratch with the Command Line Tools; `install.sh` and `inlay uninstall` run end to end in an isolated environment (another `HOME`, another install folder) |
| Window manager (tree, workspaces, commands, CLI) | The one of AeroSpace `74a1bf1`, under another name | Tests (simulated windows) |
| *Dwindle*-style auto-tiling, no *accordion* layout | Done (see [Tiling](#tiling)) | Tests (simulated windows), including a pseudorandom session of 800 steps |
| Menu bar item with *chips*, themes and Settings window | Done (see [Menu bar and settings](#menu-bar-and-settings)) | Tests and rendered images |
| Window borders | Done, with public API (see [Window borders](#window-borders)) | Tests, rendered images and `--debug-borders` on real windows |
| Tests | 651 Swift Testing tests (`scripts/test.sh`): the whole original AeroSpace suite migrated, plus the ones of Inlay | They pass with the Command Line Tools |

The "How it is verified" column says what has been verified automatically. In addition, Inlay has already been
installed and used with the Accessibility permission in two rounds (2026-10-11). In the second one, with the
version that already had the stable signature, the grid at startup, the place recovery, the *glow*, the
informational-only item and the colors per mode, no problem was noticed with the borders (no lag, no wrong
order, no orphan borders). The changes of this revision came out of that second round, and they **have not
yet been tried in real use**, only with tests: `split-target` and `min-window-size`, dialogs without a border,
6 workspaces in the shipped config, the menu bar item without a highlight on left click, the key bindings of
the menu as text, and the minimized window that goes back to its workspace. The same goes for the third
revision (installing without options, `inlay.toml` as the shipped config, the question about the symbolic link,
`inlay uninstall`, `inlay config --explain` and the reload of a config saved by hand): tried in an isolated
environment and with tests, not yet in real use. And for the latest one: the binding mode in the marker of
the focused workspace, the menu without icons, the Settings window that fits small screens, the config folder
linked by `install.sh` and `inlay uninstall` removing the config. Also untried in real use: the smart gaps and the
border hidden around a single window (`gaps.smart`, `borders.hide-when-single`) and the notice after a reload of
the config (`[notifications]`), and the four themes and seven palettes taken from Hyprland setups (`dots`,
`underline`, `glyphs`, `liquid`; `kanagawa`, `oxocarbon`, `ayu`, `one-dark`, `mono`, `material` and its `seed`,
`flexoki`): they are checked with tests and renders, including the frames of their animations.
The same goes for the curves of the animations, `seed = 'wallpaper'`, `inlay theme set` with its wallpaper
and its hooks, and the custom colors of Settings › Themes: tests and renders only. And for the latest revision:
the `labels` theme with `[menu-bar.labels]` and `[menu-bar.symbols]`, `per-monitor`, the Settings window with a
sidebar, search, undo, the export of the config and the Workspaces and Shortcuts pages, and the menu with the
layout of the focused window, the binding mode and the problems of the config.

Known limitations of this version:

- The borders are placed with a public API that does not tie them to their window: between the moment a window
  changes and the next refresh, its border may be briefly out of place or below another window.
- Apple Silicon only (the binary is `arm64`) and a single display tested.
- The interface (menu, Settings, messages) is in English.

The config format and the commands are the ones of AeroSpace with the differences described in
[Tiling](#tiling): its [guide](https://nikitabobko.github.io/AeroSpace/guide) and its
[list of commands](https://nikitabobko.github.io/AeroSpace/commands) apply, replacing `aerospace` with `inlay`.
There is a copy of that documentation in [`docs/upstream-aerospace`](./docs/upstream-aerospace).

## Requirements

- macOS 14 or later (tested on macOS 27, Apple Silicon).
- Xcode Command Line Tools with Swift 6.2 or later: `xcode-select --install`.
- Internet connection the first time it is built (SwiftPM downloads four dependencies from GitHub).

## Installation

```sh
git clone <this repo> inlay && cd inlay
./install.sh
```

No option is needed. First `install.sh` **checks every requirement** (macOS, the Command Line Tools, Swift,
`codesign`) and, if something is missing, lists it all at once with the command that fixes it
(`xcode-select --install`, which it offers to run). Then it **says what it is going to do**: where it builds,
installs and links, which signature the app gets and what happens to your config. `Continue? [Y/n]`: Enter
goes on (`--yes` skips the question). Then, in five numbered steps (`[1/5]`…`[5/5]`), it:

1. builds `Inlay.app` and signs it with a local identity, so that macOS keeps the Accessibility permission
   across rebuilds (see [Signing](#signing)). In a terminal **one line, redrawn in place, says how far the
   build is** (`132/214`, a progress bar and the time); the whole output goes to
   `~/Library/Logs/Inlay/install-<date>.log` (the last 10 are kept). If the build fails, it prints the end of
   that output, without the progress lines. `--verbose` shows everything as it comes, as does a pipe or a log;
2. installs it in `/Applications` (or in `~/Applications` if there are no permissions);
3. links the `inlay` CLI in `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`;
4. creates `~/.config/inlay/inlay.toml` as a copy of the [`inlay.toml`](./inlay.toml) of the repo, **if you
   have no Inlay config yet**. A config that already exists is yours: see
   [A config that you already have](#a-config-that-you-already-have). Then it **asks, every time, where your
   config should live**: where it is (the first option, what Enter picks) or in a folder of your own through a
   symbolic link (one you keep in a dotfiles repo, for example). See
   [Your own config folder](#your-own-config-folder). Without a terminal to ask on (stdin is not a TTY) it
   asks nothing. It checks the config with the parser of the app it has just installed and prints its errors
   and warnings (they never stop the installation);
5. **opens Inlay**.

It ends with a **summary**: the app and its signature, the CLI link (and whether it is in your `PATH`), the
config and what the parser said of it, whether Inlay is running, and what to do next: the keys of your config
that go to the workspaces, `inlay config --explain`, the menu bar item, and the Accessibility permission the
first time (see [Before opening Inlay](#before-opening-inlay)).

<p align="center"><img src="docs/images/terminal-install.png" alt="Real output of ./install.sh in a terminal: it checks the requirements, says what it is going to do and asks to continue, builds, installs Inlay.app and links the CLI in numbered steps, creates ~/.config/inlay/inlay.toml as a copy of the inlay.toml of the repo, asks where the config should live and gets ~/.dotfiles/inlay, links ~/.config/inlay to that folder, checks the config, opens Inlay and ends with a summary and what to do next" width="880"></p>

It can be run as many times as needed: it updates what is installed, quitting the running copy first.

| Option | Effect |
|---|---|
| `--reset-config` | Replaces your config by the `inlay.toml` of the repo, whatever is in it, and keeps yours next to it as `inlay.toml.backup-<date>`. See [A config that you already have](#a-config-that-you-already-have) |
| `--config-link FOLDER` | Links `~/.config/inlay` to `FOLDER` instead of asking, with the rules of [Your own config folder](#your-own-config-folder). Also on a reinstall |
| `-y`, `--yes` | Does not ask before starting. The questions about the config are still asked |
| `--no-prompt` | Asks nothing and keeps the config as it is |
| `--import-aerospace` | If you have no Inlay config, start from your `~/.aerospace.toml` instead of `inlay.toml` |
| `--no-open` | Does not open Inlay when done |
| `--adhoc-signing` | Ad hoc signature instead of the local identity (see [Signing](#signing)) |
| `--verbose` | Shows the output of the build as it comes, instead of the line that says how far it is |
| `INSTALL_DIR=…` | Folder where the app is installed |
| `INLAY_BIN_DIR=…` | Folder where the CLI is linked |

With `--import-aerospace` your `aerospace.toml` is copied as is (if it is a symbolic link, the file it points to
is copied and the original is not touched). Check three things in the copy: `start-at-login = true` would make
Inlay add itself to the login items the first time it starts; the key bindings or scripts that call the
`aerospace` CLI keep talking to AeroSpace and must call `inlay`; and with `gaps` of 8 or less the borders of
two neighboring windows touch.

### Your own config folder

On every run, also when you already have a config, `install.sh` asks:

```
? Where should your config live?  ↑↓ · Enter
  ❯ Keep ~/.config/inlay           where it is now · 481 lines
    Link ~/.dotfiles/inlay         has inlay.toml
    Link ~/dotfiles/.config/inlay  no inlay.toml: gets a copy of the repo's
    Another folder...              type its path
```

Move with the arrows (or `j`/`k`, or the number of an option) and press Enter; Enter alone keeps what you have.
The list has the folders of a dotfiles repo that it finds; "Another folder..." asks for a path (`~` is
expanded, and Tab completes it). The folder you pick becomes the target of **a symbolic link,
`~/.config/inlay`**. Inlay reads and writes the `inlay.toml` in it; nothing else in the folder is touched. A
typed path that doesn't work (a typo, a file, a folder you don't want to fill) is asked again, and Enter with
nothing keeps your config as it is. In a terminal the output has colors and the list is a menu; with
`NO_COLOR` set it is a numbered list, and in a pipe or a log it is plain text.

| What it finds | What it does |
|---|---|
| A typed folder does not exist | Says so, suggests a folder of the list with the same name if there is one, and asks again. With `--config-link`, links nothing: your config stays as it is (on a new install, the copy of `inlay.toml` in `~/.config/inlay/`) |
| A folder of the list has no `inlay.toml` | The list says so, and picking it copies the `inlay.toml` of the repo into it |
| A typed folder has no `inlay.toml` | Warns and asks `Copy the inlay.toml of the repo into <folder>? [y/N]`. With no, nothing is copied and it asks for another folder (with `--config-link`, nothing is linked) |
| You had a real `~/.config/inlay` | It is not deleted: it is renamed to `~/.config/inlay.backup-<date>`, and the script says so |
| `~/.config/inlay` is already a link | The first option is `Keep the link`, and says where it points. Linking another folder replaces only the link: the folder it pointed to is not touched |
| Only the file is linked (`~/.config/inlay/inlay.toml -> your file`, the way a previous version did it) | It keeps working and Enter leaves it alone. The folder that holds your file is in the list, and picking it makes the old `~/.config/inlay` the backup |
| Your config is `~/.inlay.toml` | The question is skipped: Inlay reads one file or the other, never both |

`--config-link FOLDER` does the same without asking (a folder without `inlay.toml` is only filled in when
there is a terminal to ask on), and `--no-prompt` skips the question. To stop using your folder, remove the
link (`rm ~/.config/inlay`) and run `./install.sh` again.

### A config that you already have

`install.sh` never edits or deletes a config, and it replaces one only in two cases, always keeping the old
one next to the new one as `inlay.toml.backup-<date>` (`inlay.toml.backup-20261012-153000`):

- **It is a default config of a previous version of Inlay, exactly as it was installed.** The script
  compares it, byte for byte (SHA-256), with every default config that Inlay has shipped
  ([`scripts/default-config-hashes.txt`](./scripts/default-config-hashes.txt)). If it is one of them, nobody
  has edited it, so it is replaced by the current `inlay.toml` and the script says so. This is what updates a
  Mac that was installed when the default config was still the one of AeroSpace: `alt-…` key bindings and
  no rule that sends a window to a workspace, so every window stayed in the workspace on the screen.
- **You pass `--reset-config`**, or answer `Use the repo's inlay.toml` to the question about what your config
  lacks. Whatever the config is, it is replaced by the `inlay.toml` of the repo.

Any other config is **kept as it is**, and the script **lists the settings of the `inlay.toml` of the repo that
yours doesn't have** (up to 8, and how many more), with their table: `+ [gaps]  smart = true`. A key binding
counts as present when your config has its command under another key. It also tells if the config has no
`on-window-detected` rule. When something is missing and there is a terminal, it asks `What now?`: keep yours
(Enter), show the whole diff (in `less`), or use the `inlay.toml` of the repo, keeping yours as
`inlay.toml.backup-<date>`. A config in a linked folder can only be kept: edit it in your folder. Without a
terminal it prints the two commands that matter: `./install.sh --reset-config` and a `diff`. A config changed
from the Settings window counts as edited: it is kept.

A config that is reached through a **symbolic link** (a linked folder, or a linked file) is always taken for
your own, whatever is in it: it is never replaced on its own. `--reset-config` never writes, moves or deletes
what a link points to either:

- with a **linked folder**, the link itself is renamed to `~/.config/inlay.backup-<date>` (it still points to
  your folder) and `~/.config/inlay` becomes a real folder with the `inlay.toml` of the repo. The script prints
  the command that links your folder again;
- with a **linked file**, the link is renamed to `inlay.toml.backup-<date>`, still pointing to your file.

To go back to a backup: `mv ~/.config/inlay/inlay.toml.backup-<date> ~/.config/inlay/inlay.toml`.
After changing `inlay.toml` in the repo, `scripts/update-default-config-hashes.sh` adds it to the list (a test
fails until it is there).

### Before opening Inlay

- **Quit AeroSpace, AeroMenu and `borders` (JankyBorders).** They do the same job, and two window managers at
  once fight over the windows. `install.sh` never quits another app: if it detects any of them running, it
  installs everything, explains why it did **not** open Inlay and prints the command to open it once you have
  quit them. Inlay can be *installed* alongside AeroSpace without any problem: they share no config, socket,
  preferences or identifier.
- **Accessibility permission.** Inlay moves the windows with the Accessibility API. The first time, macOS asks
  for the permission: enable it in *System Settings › Privacy & Security › Accessibility* (you need to be an
  administrator; on a managed machine that list may be locked). As long as it does not have it, Inlay does
  nothing: its menu bar item shows a warning triangle and the CLI answers "Can't connect to Inlay server".
  Once it has it, Inlay sends the windows that are already open to the workspaces of their rules and arranges
  them (see [Tiling](#tiling)).
  If Inlay appears enabled in the list but keeps asking for it (it happens after rebuilding with an ad hoc
  signature), remove it from the list with the "−" button and open Inlay again.

### Signing

macOS ties the Accessibility permission to the signature of the app. That is why `install.sh` signs **by
default with a stable identity**: it creates, only once, a self-signed identity ("Inlay Local Code Signing") in
your login keychain and signs with it, so the permission is kept across builds. macOS may ask for the keychain
password the first time `codesign` uses the key: choose "Always Allow". If the identity cannot be created or
used, the app is signed ad hoc and a warning is shown.

On a Mac where the identity does not exist yet (a fresh clone on another machine) the same `./install.sh`
creates it: nothing has to be passed.

With `--adhoc-signing` the identity is not used: the ad hoc signature is enough to run Inlay on this Mac, but
the permission is lost **every time it is rebuilt** and has to be granted again. (`--stable-signing` is still
accepted: it is now what is done by default.)

`scripts/build-app.sh` signs with that identity if it already exists (it never creates it) and ad hoc if not;
`scripts/build-app.sh --sign-identity -` forces the ad hoc signature.

### Configuration

Inlay reads `~/.config/inlay/inlay.toml` (or `$XDG_CONFIG_HOME/inlay/inlay.toml`) or else `~/.inlay.toml`; if
both exist, it warns about the ambiguity and loads neither. The app, the CLI and the Settings window all use
that same file. (`XDG_CONFIG_HOME` only counts if it is set for the apps that macOS starts, not just in your
shell: `install.sh` warns when it sees it set.)

**The shipped config is [`inlay.toml`](./inlay.toml), at the root of the repo.** It is the file that
`install.sh` copies, and a copy of it travels inside the app as the fallback for when there is no config at
all. It is a real config rather than a neutral sample: 7 persistent workspaces, key bindings on
`cmd-alt-ctrl-…` and `cmd-alt-shift-…`, the `service` and `resize` modes and `on-window-detected` rules that
send each app to its workspace. Make it yours by editing your copy, or keep your config in a folder of your
own and link it (the question of `install.sh`, or `--config-link`).

The rules are checked from top to bottom, and **the first one that matches a window is the only one that runs
for it** (a rule with `check-further-callbacks = true` lets the next ones run too; the shipped config has
none). In `inlay.toml` they come in this order:

1. the panels to open or save a file float where they open;
2. the apps with a workspace go to it: terminals to 1, editors to 2, browsers to 3, chats to 4, AI to 5;
3. the quick apps (Finder, System Settings, Calculator…) and the settings window of any app float where they
   open;
4. **every other window floats where it opens**, until you put it in a layout.

The last rule is a catch-all one:

```toml
[[on-window-detected]]
if = 'test %{window-layout} ~= _tiles'   # h_tiles or v_tiles: a tiling window
run = 'layout floating'
```

It only matches the windows that Inlay tiles. What Inlay takes for a dialog (a sheet, an alert, an "About"
window) is already floating when the rules run, so it does not match and stays where it opens; popups never
get to the rules. The window of an app without a rule floats in the workspace on the screen, where the app
opens it, and the tiled windows don't move. **`cmd-alt-shift` + a workspace key (`j k l i o p`) puts it in
the layout**: the keys run `layout tiling` and then `move-node-to-workspace`, so the window stops floating and
goes to that workspace, or takes its place in the workspace on the screen if it is that one. To give an app
a place of its own, give it a rule above (a workspace of its own); to have every other window tiled in the
workspace where it opens, as AeroSpace does, delete the rule. Like every rule it runs once per window: a
window that you tile stays tiled, until you run the rules again by hand (`w` in the `service` mode).

**Every key is documented in [`docs/config-reference.toml`](./docs/config-reference.toml)**: what it does,
its possible values and its default, for the keys inherited from AeroSpace and for the ones of Inlay. The
`inlay` CLI prints it, without needing Inlay to be running:

```sh
inlay config --explain                 # the whole reference
inlay config --explain borders.width   # one key
inlay config --explain tiling          # one table ([menu-bar] also prints [menu-bar.colors])
inlay config --explain gaps.inner      # a group of keys
```

<p align="center"><img src="docs/images/terminal-cli.png" alt="Real output of two commands in a terminal: 'inlay config --explain borders.width' prints the [borders] table header, the comment that explains the key, its possible values (1 ... 20), its fallback value and 'width = 4'; 'inlay list-workspaces --all' prints the workspaces 1 to 6, one per line" width="880"></p>

A test fails if the config parser accepts a key that the reference does not document, or the other way round.

**The file and the Settings window stay in sync in both directions.** Settings writes its changes to the file
(see [Menu bar and settings](#menu-bar-and-settings)). In the other direction, with
`auto-reload-config = true` (it is set in the shipped `inlay.toml`; the default of the key is `false`), Inlay
reloads the config when the file is saved by hand, and the Settings window, if it is open, the menu bar item
and the borders show the new values right away, without closing anything. It works when `~/.config/inlay` is
a symbolic link to a folder of yours, when the file itself is a link, with editors that save by writing a new
file and renaming it over the old one, and when a link is pointed somewhere else. A save that leaves the file unreadable as TOML
is not applied (the previous config stays, and a window shows the error); the next save is picked up as usual.
Without that key, reload by hand: `inlay reload-config` or *Reload Config* in the menu, which refresh
Settings the same way. Settings writing the file does not cause a second reload.

```toml
auto-reload-config = true   # the default is false: reload with 'inlay reload-config' or from the menu
```

![Illustration, animated: on the left the config file, on the right the Borders tab of Settings (a real render). The line 'width = 4' of the file is changed to 'width = 8' and the Width slider of Settings moves to 8 pt; then the slider is moved to 2 pt and the line of the file becomes 'width = 2'](docs/images/settings-sync.gif)

**A reload says what it changed.** After *Reload Config* in the menu, a save picked up by `auto-reload-config`, or
`inlay reload-config` and a key binding when the file changed since the last load, a notice shows up for a moment in the top right corner of the screen of the focus:
`inlay.toml reloaded` and the keys that changed, with the old and the new value (`borders.width 4 → 8`). Comments
and formatting don't count, and after four keys it says how many more. With warnings it stays longer and says how
many; a config with errors shows its window instead. It never takes the focus: the mouse over it keeps it, and a
click dismisses it. There is no notice at startup, nor for a change made in Settings, which shows it already.
`--no-gui` skips it.

```toml
[notifications]
    on-reload = 'diff'   # 'diff' | 'simple' (only the name of the file) | 'off'
```

**Problems are never silent.** If the config has errors or warnings, `inlay reload-config` prints them, a
window lists the errors, and the menu of the menu bar item shows "Config contains errors…" or "Config contains
warnings…". A key binding that macOS refuses to register (another app may own the same keys) is reported the
same way, as a warning that names the binding. While *Secure Input* is active (a password field is focused),
macOS delivers no key bindings to anybody: Inlay shows a shield in the corner of the screen. To check a file
without loading it:

```sh
/Applications/Inlay.app/Contents/MacOS/Inlay --check-config ~/.config/inlay/inlay.toml
```

The programs that Inlay launches receive the variables `INLAY_WINDOW_ID`, `INLAY_WORKSPACE`,
`INLAY_FOCUSED_WORKSPACE` and `INLAY_PREV_WORKSPACE` (and also under the `AEROSPACE_*` name, so that scripts
written for AeroSpace keep working).

### Gaps

The `[gaps]` table sets, in points, the gaps between windows (`inner.*`) and between the windows and the edges of
the monitor (`outer.*`). A key that is omitted is 0. A value can also depend on the monitor
(`outer.top = [{ monitor.main = 16 }, 24]`: see `inlay config --explain gaps`).

```toml
[gaps]
    inner.horizontal = 8   # between two windows that are side by side
    inner.vertical =   8   # between two windows that are one above the other
    outer.left =       8
    outer.bottom =     8
    outer.top =        8   # under the menu bar
    outer.right =      8
```

![Illustration, animated: a screen with three tiled windows and borders of 4 points, drawn with four configs in turn. With all the gaps at 0 the borders of neighbors overlap and the screen cuts them; with 8 points, the values of the shipped config, the borders touch; with 16 points there is air between them; and with inner.horizontal = 48 and outer.top = 56 only the gap between the columns and the gap under the menu bar grow](docs/images/gaps.gif)

The window borders are drawn in the gaps: see [Window borders](#window-borders) for how the two fit together.

**Smart gaps** (`smart`, `false` by default; `true` in the shipped config): a workspace with a single tiling
window has no outer gaps and no border, and the window takes the whole visible part of the screen, under the menu
bar and above the Dock. The gaps and the border come back as soon as a second tiling window joins it, sliding like
any other change of the layout. `fullscreen` keeps it that way: the single window goes on filling the screen
without gaps. Floating windows don't count, and keep their borders. It is also in **Settings › Gaps**.

```toml
[gaps]
    smart = true   # a single tiling window: no outer gaps
```

### Tiling

A new window **splits the focused window in two**, like the *dwindle* layout of Hyprland: if the focused one is
wider than it is tall they end up side by side; otherwise, stacked. The new one goes to the right or below.
When a window is closed, its neighbor gets the space back.

![Illustration, animated: with new-window-placement = 'dwindle', five windows open one after another. The first one takes the whole workspace; the second one splits it side by side; the third one splits the second one, which is taller than wide, in two stacked halves; the fourth and the fifth keep splitting the focused window, in a spiral. Then they are closed one by one and every time the neighbor gets the space back](docs/images/tiling-dwindle.gif)

```toml
[tiling]
    new-window-placement = 'dwindle'   # or 'after-focused': the behavior of AeroSpace
    split-ratio = 0.5                  # 0.1 – 0.9: fraction kept by the window that is split
    split-target = 'focused'           # or 'cursor': the new one splits the window under the cursor
    startup-layout = 'grid'            # 'grid' | 'row' | 'dwindle': the windows that were already open
    min-window-size = 100              # 20 – 500 pt: how far `resize` and the mouse can shrink
```

**How much each one gets** (`split-ratio`, only with `dwindle`): the fraction of its space that the window that
is split keeps, from 0.1 to 0.9. With 0.5, two halves; with 0.6, it keeps 60% and the new window gets 40%.

```toml
[tiling]
    split-ratio = 0.5
```

![Illustration, animated: three screens side by side with split-ratio = 0.3, 0.5 and 0.7. A second window opens in each one: the first window keeps 30%, 50% and 70% of the width, and the new window gets the rest](docs/images/tiling-split-ratio.gif)

**Which window is split** (`split-target`, only with `dwindle`): with `'focused'` (the default), the focused
one; if the focused one is not tiled in that workspace, the most recent tiled one. With `'cursor'`, the tiled
window under the mouse cursor, as in Hyprland; if there is none (the cursor is in a gap, on another monitor or
over a fullscreen window, or the target workspace is not visible), `'focused'` applies. Floating windows do
not count: under a floating one, the tiled window behind it is considered.

```toml
[tiling]
    split-target = 'focused'   # or 'cursor'
```

![Illustration, animated: two screens with the same three windows, the focus on window 1 and the mouse cursor over window 3. A fourth window opens. With split-target = 'focused' it splits window 1 and appears below it; with split-target = 'cursor' it splits window 3 and appears to its right](docs/images/tiling-split-target.gif)

**Minimum size** (`min-window-size`, 100 pt by default): the `resize` command and dragging an edge with the
mouse stop shrinking a window when it reaches that width or height, and they do not shrink the neighbors below
it either when the other one is the one growing (the neighbors that still have room give up the rest). With
the mouse, the edge that was dragged beyond it goes back to the limit on release. Reaching the limit is not an
error: `resize` exits with code 0 and no message, the same as before (it has no `--fail-if-noop`), because in
a resize mode with the key held down the limit is reached continuously. It only limits resizing: if the
windows of a workspace do not fit with that size (many windows on a small monitor, or a window split several
times), the distribution gives them less, down to the safety floor of the layout (the inner gap plus 1 pt),
and `resize` simply does not shrink them any further. `resize` always works in screen points.

```toml
[tiling]
    min-window-size = 100   # 20 ... 500 points
```

![Illustration, animated: two windows side by side. 'resize width -50' is run again and again on the left one, whose width goes down from 616 points in steps of 50 until it reaches a dashed line marked 'min-window-size = 100', where it stays at 100 points however many more times the command runs](docs/images/tiling-min-window-size.gif)

Both keys are also in **Settings › Tiling** ("Window to split" and "Minimum window size").

The windows that **are already open when Inlay starts** (or when it is resumed with `inlay enable on`) are not
placed one by one. First the `on-window-detected` rules of the config run for each of them, exactly as for a
new window, so every window goes to the workspace of its rule (or becomes floating, or whatever the rule
says). Then the windows are distributed, workspace by workspace, according to `startup-layout`. With the
shipped config, the terminals end up in workspace 1, the editors in 2, the browsers in 3, and so on, the
windows of the apps without a workspace in 6, each workspace with its own grid. The workspaces are arranged
once the rules of every window are over, also when macOS reports another event in the middle of the startup. The rules run once per window: later refreshes do not evaluate them again, so a
window that you move somewhere else stays there. On resume, they only run for the windows that appeared
while Inlay was paused. To run them again for all the open windows, use
`inlay run-callback on-window-detected --for-every-window` (`w` in the `service` mode of the shipped config).

| `startup-layout` | Result |
|---|---|
| `'grid'` (the default) | Balanced grid: `ceil(√n)` columns and as many rows as needed, all rows with the same height. The last row shares its width among the windows it has: 5 windows are 3 on top and 2 below; 3 are 2 on top and 1 below |
| `'row'` | A single row with all the windows at the same width |
| `'dwindle'` | No distribution: each window enters as a new window, one after another (with `new-window-placement = 'dwindle'`, a spiral with the last ones very small) |

```toml
[tiling]
    startup-layout = 'grid'   # 'grid' | 'row' | 'dwindle'
```

![Illustration, animated: three screens with the same five overlapping windows, as they were before Inlay started, which are then arranged at once. With startup-layout = 'grid': three windows on top and two below. With 'row': a single row of five windows of the same width. With 'dwindle': a spiral, with the first window on the left half and the last two very small](docs/images/tiling-startup-layout.gif)

It only affects that moment. The windows you open afterwards follow `new-window-placement`, and the grid is a
normal tree: it can be moved, resized and rearranged with the usual commands. When resuming after a pause,
only the workspaces in which some window appeared while Inlay was paused are rearranged; the others keep
their arrangement. It is also in **Settings › Tiling**.

A window that leaves the tiling because macOS **minimizes** it, puts it in **native fullscreen** or **hides
its app** remembers its place (container, position, size and the neighbor that kept its space) and gets it
back when it returns:

- If its container still exists, it goes back to its position and the neighbor gives the space back.
- If the container is gone (it had only two windows and was flattened), the neighbor is split again the same way as before.
- If neither the container nor the neighbor is left, it enters as a new window.

![Illustration, animated: three tiled windows, with a small browser window at the bottom right. The browser is minimized to the Dock and the window above it, the editor, takes its space; when the browser is restored it gets its place and its size back, and the editor gives the space back](docs/images/tiling-minimize.gif)

A **minimized** window also remembers its workspace (a minimized window does not belong to any). If it is
restored while you are in another workspace, it goes back to its own and to its place, and **the focus follows
it**: Inlay switches to that workspace. If the place is no longer recoverable, it enters its workspace as a new
window. Only if its workspace no longer exists (it was not persistent and was left without windows) does it
enter as a new window in the focused workspace.

Inlay **has no *accordion* layout**. To be able to use an `aerospace.toml` as is, its forms are accepted with
a warning (not with an error) and are treated as `tiles`:

| In the `aerospace.toml` | In Inlay |
|---|---|
| `default-root-container-layout = 'accordion'` | `'tiles'` is used |
| `accordion-padding = 30` | Ignored |
| `layout accordion`, `layout h_accordion`, `layout v_accordion` | `layout tiles`, `layout h_tiles`, `layout v_tiles` |
| `layout tiles accordion` (toggle) | `layout tiles` |

The warnings show up in `inlay reload-config` and in the menu of the menu bar item ("Config contains warnings...").

### Moving windows: `swap` and `move`

The shipped config has two ways of moving the focused window with the arrows:

- **`cmd-alt-ctrl` + arrow: `swap`**. The window trades places with its neighbor and the layout keeps its
  shape: in a left column with two windows and a right one, the bottom left window moved to the right takes the
  place of the right one, and the right one goes to the bottom left. Toward a side with two windows, it swaps
  with the one that was focused more recently. At the edge of the workspace nothing happens.
- **`cmd-alt-shift` + arrow: `move`**, the one of AeroSpace. The window leaves its column or row and the layout
  changes its shape (the bottom left window moved to the right becomes a third column).

### Animations

The tiling windows **slide to their place**, in 180 ms, when a window opens (it grows from the center of its
tile while its neighbor makes room for it, like the *popin* of Hyprland) or closes, when a window is moved with `swap` or `move`,
and when the `fullscreen` command (`cmd-alt-ctrl-enter`) makes a window grow from its tile to the whole screen, or
shrink back to its tile. The native fullscreen of macOS has an animation of its own.
The borders go with them. Switching workspaces has its own slide (below). Nothing else is animated: resizing, `balance-sizes`, the
startup and the mouse stay instant. With *Reduce motion* (System Settings → Accessibility → Display) nothing is
animated. Settings has the same keys in its **Animations** tab.

**Switching workspaces** slides the windows too, in the same duration: the windows of the workspace you leave
go out by one side of the screen and the ones of the workspace you go to come in by the other. Toward a later
workspace (in the order of the menu bar item) they move to the left, toward an earlier one to the right. Only
the tiling windows slide: the floating ones appear and disappear as before.

The windows never cross another screen. `workspace-switch` picks the direction, and each screen that switches
workspace applies it as far as the screens around it allow:

| `workspace-switch` | No screen around | A screen on one side | Screens on both sides | A screen below |
|---|---|---|---|---|
| `'horizontal'` (default) | Side to side | In and out by the free side | No slide | Side to side |
| `'vertical'` | Through the bottom | Through the bottom | Through the bottom | No slide |
| `'auto'` | Side to side | Through the bottom | Through the bottom | Side to side |

Through the bottom means out downwards and in from below: macOS doesn't let a window above the menu bar, so the
top of a screen can't be used. `'off'` turns the slide off and keeps the other animations.

```toml
[animations]
    enabled = true
    duration = 180                    # 0 ... 500 milliseconds. 0 = no animation
    workspace-switch = 'horizontal'   # 'horizontal' | 'vertical' | 'auto' | 'off'
```

macOS only lets Inlay move the windows of other apps through the Accessibility API, one frame at a time, and
it doesn't let it change their opacity or scale without disabling SIP: the animation moves and resizes the
windows, nothing more. A window that is slow to resize (some browsers, Electron apps) skips frames, but it
always ends in its exact place.

**Curves**: how the movement is spread over the duration, a cubic Bézier curve like the `bezier` of Hyprland. The
presets are `ease-out` (the default, and the curve of before), `linear`, `ease`, `ease-in-out`, `snappy` and
`overshot` (the window goes a bit past its frame and comes back); `[animations.curves]` adds your own. Each kind
of animation can have its own curve and duration: `open` (a new window), `move` (the others make room or take the
space, `swap`, `move`), `fullscreen` and `workspace`.

```toml
[animations]
    curve = 'ease-out'
    open = { curve = 'overshot', duration = 220 }
    workspace = { curve = 'snappy', duration = 160 }

    [animations.curves]
        bounce = [0.34, 1.56, 0.64, 1]   # x1, y1, x2, y2. x1 and x2 in 0 ... 1
```

A curve that overshoots also resizes the window past its tile for a moment: some apps are slow to redraw that.

## Menu bar and settings

The menu bar item shows **all the workspaces** and marks the focused one (it does not distinguish monitors). It
is configured in the `[menu-bar]` table of the config; `inlay config --explain menu-bar` documents it.

<p align="center"><img src="docs/images/menu-bar-states.png" alt="Real render of the menu bar item, enlarged, with callouts: workspace 2, the focused one, has a solid background; the workspaces with windows have a faint background; the empty workspace 6 is dimmed and has no background. On the right, four more states: an outline around the focused workspace when it has a fullscreen window, a hollow square for the same in the 'square' theme, a pause sign when Inlay is paused, and a warning triangle when the Accessibility permission is not granted yet" width="880"></p>

| Key | Values | Default |
|---|---|---|
| `enabled` | `true`, `false` | `true` |
| `theme` | `'pills'`, `'chips'`, `'square'`, `'minimal'`, `'dots'`, `'underline'`, `'glyphs'`, `'liquid'`, `'labels'` | `'liquid'` |
| `dim-empty-workspaces` | `true`, `false` | `true` |
| `show-mode` | `true`, `false` | `true` |
| `per-monitor` | `true`, `false` | `false` |
| `[menu-bar.labels]`, `[menu-bar.symbols]` `<workspace>` | a name, an SF Symbol (only for `'labels'`) | empty tables |
| `[menu-bar.colors]` `accent`, `focused`, `occupied`, `empty` | color or `'auto'` | `'auto'` |

**`theme`**: the shape of the item.

```toml
[menu-bar]
    theme = 'liquid'  # 'pills' | 'chips' | 'square' | 'minimal' | 'dots' | 'underline' | 'glyphs' | 'liquid' | 'labels'
```

<p align="center"><img src="docs/images/menu-bar-themes.png" alt="Real render of the eight themes of the menu bar item, each on a dark and on a light menu bar. 'pills': round workspaces and 2, the focused one, a wider pill. 'chips': the numbers 1 to 6 as chips, 2 with a solid background. 'square': the numbers, and a filled square in place of the focused workspace. 'minimal': only the chip of the focused workspace, 2. 'dots': six dots, the second one a pill and the sixth a ring. 'underline': the numbers, 2 with a bar under it. 'glyphs': discs, a target on 2 and a ring on 6. 'liquid', the default: small dots and a round drop with the 2 in it" width="880"></p>

When the focus moves, the marker slides from the workspace it leaves to the new one (not in `minimal`). The
four themes taken from Hyprland setups move in their own way: the pill of **`dots`** stretches on its way,
like the page indicator of iOS; the bar of **`underline`** leaves by its leading edge, stretches towards the
new workspace and then shrinks into it; the target of **`glyphs`** fades from one workspace to the other; and
the drop of **`liquid`** flows to the new workspace with a trail behind it that catches up at the end. With
"Reduce motion" nothing slides.

**`labels`** draws an SF Symbol per workspace, and stretches the focused one into a pill with its symbol and its
name: the purpose of each workspace at a glance. The names and the symbols are two tables of the config that
**only this theme uses**: the other themes ignore them, so they can stay in the file while another theme is in use.
A workspace without a symbol (or with a name that isn't an SF Symbol) shows its own name, and one without a label
shows its name in the pill. Settings › Themes › Indicator edits them, with a preview of each symbol, when the theme
is `labels`.

```toml
[menu-bar]
    theme = 'labels'

[menu-bar.labels]
    1 = 'Terminals'
    2 = 'Code'

[menu-bar.symbols]                  # the names of the SF Symbols app
    1 = 'terminal'
    2 = 'chevron.left.forwardslash.chevron.right'
```

**`per-monitor`** groups the workspaces by the monitor they are on, from left to right, with a line between
the monitors, and draws a hollow marker on the workspace that another monitor shows. With a single monitor it
changes nothing. Every theme supports it.

The item shows no app icons. `theme = 'chips-icons'` and the `show-app-icons` key, of a previous version, are
still accepted so that a config that has them loads (the Settings window wrote them): they give a warning,
the theme is treated as `'chips'` and the key is ignored. Picking a theme in Settings removes both.

**`[theme] palette`**: the colors of the item **and** of the borders, from a palette of the Hyprland world:
`'catppuccin'`, `'tokyo-night'`, `'gruvbox'`, `'nord'`, `'rose-pine'`, `'dracula'`, `'everforest'`, `'kanagawa'`,
`'oxocarbon'`, `'ayu'`, `'one-dark'`, `'mono'` (black, white and grays), `'material'` or `'flexoki'`. Each one has
a light and a dark variant, and the one of the appearance of the system applies (it changes with it). A palette
only gives the colors you left at their default: the ones of `[menu-bar.colors]` that are `'auto'`, and the
three colors of `[borders]`; a color you wrote there wins. `'one-dark'` is the default; `'system'` is no palette. The
**Themes** tab of Settings picks it.

```toml
[theme]
    palette = 'one-dark'     # system | catppuccin | tokyo-night | gruvbox | nord | rose-pine | dracula | everforest
                             # | kanagawa | oxocarbon | ayu | one-dark | mono | material | flexoki
    seed = '#6750A4'         # only for 'material': '#RRGGBB' or 'system-accent'
```

**`'material'`** is Material You: its colors are made from a single color, **`seed`**, the way matugen makes
them from a wallpaper. They keep the hue of the seed, and each one has the lightness that Material gives to its
role (the focused workspace and the active border, the accent and the floating border, the grays). The default
seed gives the colors of the Material 3 baseline, and `seed = 'system-accent'` makes the palette from the accent
color of macOS. It is an approximation of Material in CIELAB: the colors are close to the ones of matugen, not
equal. The other palettes ignore `seed`.

**`seed = 'wallpaper'`** makes it from the main color of the wallpaper of the main screen, like matugen: the hue
that covers the most of the image, weighted by how colorful it is. It is read when the config loads and every time
the wallpaper changes: Inlay watches the store of the wallpapers of macOS, with no timer, and reads a thumbnail of
64×64 points (a few milliseconds). A wallpaper that isn't an image (the Aerial videos) gives the default seed.

**Themes: `inlay theme set <palette>`** switches the palette from the terminal (`inlay theme list` lists them, and
the one in use). A theme is the palette and, optionally, its wallpaper and the commands that theme your other apps:

```toml
[theme]
    palette = 'one-dark'
    wallpaper = '~/walls/default.jpg'       # the one of every palette (optional)
    on-change = ['~/.config/ghostty/set-theme.sh']

    [theme.wallpapers]                      # the ones of some palettes, which win
        gruvbox = '~/walls/autumn.jpg'
```

- **The wallpaper** is put on every screen when the palette changes (`theme set`, Settings › Themes or the file),
  never at startup: a wallpaper picked in System Settings stays until the next change of palette. Without one,
  switching palettes leaves the wallpaper alone. If the file doesn't exist anymore, Inlay asks: *Choose…* picks
  another image and writes it in the config (in `[theme.wallpapers]` if it was the one of the palette), *Keep
  Current* leaves the wallpaper on the screen.
- **The hooks** of `on-change` run when the colors change: another palette, the other variant (light or dark), a
  new seed. They get the colors in effect as `INLAY_THEME_FOCUSED`, `INLAY_THEME_OCCUPIED`, `INLAY_THEME_EMPTY`,
  `INLAY_THEME_ACCENT`, `INLAY_THEME_ACTIVE_BORDER`, `INLAY_THEME_INACTIVE_BORDER`, `INLAY_THEME_FLOATING_BORDER`
  ('#RRGGBB'), and `INLAY_THEME`, `INLAY_THEME_VARIANT`, `INLAY_THEME_SEED` and `INLAY_THEME_WALLPAPER`.
- **Colors set by hand win** over the palette. `inlay theme set <palette>` keeps them and says which ones;
  `--reset-colors` removes them, so that the palette gives every color.

**Settings › Themes** is where the look is decided, in one place. On top, always: the live preview, a small desktop
with the menu bar item and three windows with their borders, and over it a chip that says where the colors come
from, green with the name of the palette (every color comes from it), orange *Custom* (some colors are your own,
the rest come from the palette, and *Reset to Theme* gives them all back to it) or gray *No theme*. A *Dark* /
*Light* switch shows the other variant of the palettes, without changing the appearance of the system. Below it,
three parts, one at a time:

- **Palette**: *Made for You* (System, Material · Wallpaper, Material · Color, with the seed when it is a color) and
  the other palettes, each one as a miniature with its menu bar item and two windows with their borders. The mouse
  over a palette shows it in the preview, without writing anything; a click uses it. While some colors are your
  own no palette is selected: the one that gives the rest is drawn dashed, as the *base*, and picking a palette
  asks first, since it removes your colors. Below, the wallpaper of `[theme]` (*Choose…*, *Remove*) and the hooks
  of `on-change`, which are edited in the file.
- **Indicator**: the nine shapes of the menu bar item, the names and symbols of the `labels` theme when it is the
  one in use, and the options (*Dim empty workspaces*, *Show the binding mode*, *Group by monitor*).
- **Colors**: every color that a palette gives, the ones of the indicator (active, inactive and empty workspaces,
  binding mode) and the ones of the borders (active, inactive, floating). Each one starts as the one of the theme
  (a *Theme* badge); changing it makes it yours (*Custom*), and *Use Theme* gives it back.

The Borders page keeps the rest of its options, and General the switch of the menu bar item; the colors are only
in Themes.

<p align="center"><img src="docs/images/menu-bar-palettes.png" alt="Real render of the pills theme in the fourteen palettes, the dark variant on a dark menu bar and the light one on a light menu bar: Catppuccin with a mauve focused pill, Tokyo Night blue, Gruvbox yellow, Nord frost blue, Rosé Pine rose, Dracula purple, Everforest green, Kanagawa blue, Oxocarbon magenta, Ayu yellow and orange, One Dark blue, Mono white and black, Material You lavender and purple, Flexoki orange; and Material You with seed '#B5651D', in peach and brown" width="880"></p>

**`dim-empty-workspaces`, `show-mode`**: what the item shows besides the names. With
`enabled = false` there is no item at all, and Inlay keeps working with the key bindings and the CLI.

```toml
[menu-bar]
    enabled = true
    dim-empty-workspaces = true
    show-mode = true              # the initial of the binding mode on the marker of the focused workspace
```

With `show-mode = true`, while the binding mode is not `main` (`resize`, `service`…), **the marker of the
focused workspace carries the initial of the mode**, the way Aeromenu did it. In `chips` and `minimal` the
initial takes the place of the name in the chip; in `square` the square grows from 8.5 to 14 pt to hold it.
In `dots` the pill grows taller to hold it, in `glyphs` the target becomes a disc with the initial, in
`underline` the initial takes the place of the name and in `liquid` the drop shows it.
Nothing is added next to the workspaces, so the item is exactly as wide in every mode and nothing in the menu
bar moves. While a window of the workspace is fullscreen, the marker is an outline and the initial is drawn
inside it. The key governs every theme (`square` used to show the mode always).

<p align="center"><img src="docs/images/menu-bar-options.png" alt="Real render of the options of the menu bar item. dim-empty-workspaces: with true the empty workspace 6 is fainter, with false it only lacks the background. show-mode: the plain item with false or in the main mode; with true, in the resize mode, an R in the chip of the focused workspace in 'chips' and in 'minimal', and in a larger square in 'square', the item as wide as before; and the same with a fullscreen window, the R inside of an outline" width="880"></p>

**`[menu-bar.colors]`**: a color is `'#RRGGBB'`, `'#RRGGBBAA'` or `'system-accent'`. `'auto'` is the color of
the menu bar text (white on a dark bar, black on a light one). With everything set to `'auto'`, the
item is a template image identical to the one of Aeromenu, also while it shows a binding mode; a fixed color
does not adapt to the bar. `accent` is the color of the marker while it shows the binding mode: `'auto'` is
the same as `focused`, and over a fixed color the initial is white, or black if the color is light.

```toml
[menu-bar.colors]
    accent = 'auto'            # the marker of the focused workspace while it shows the binding mode
    focused = 'auto'           # the background of the focused workspace
    occupied = 'auto'          # the workspaces with windows: the name and, at 16%, its background
    empty = 'auto'             # the workspaces without windows
```

<p align="center"><img src="docs/images/menu-bar-colors.png" alt="Real render of the colors of the menu bar item, with three configs and their TOML, each on a dark and on a light bar. The defaults: white or black chips that follow the bar, the R of the resize mode cut out of the focused one. accent = 'system-accent': that chip in the accent color of the system, with a white R. Custom colors (accent '#E06C75', focused '#D19A66', occupied '#ABB2BF', empty '#6B7280'): the same colors on both bars, also shown in the 'square' theme. And focused = 'system-accent': the focused workspace in the accent color" width="880"></p>

**The item and its menu**

<p align="center"><img src="docs/images/menu.png" alt="Illustration of the menu that a click on the item opens, from top to bottom: Workspace 2 with its windows (Editor checked, Terminal), by the name of their app; Float Focused Window; then Reload Config, Open inlay.toml, Pause Inlay and Settings, the version ('Inlay 0.1.0') and Quit Inlay" width="720"></p>


- A **click** on the item (the left button) opens the menu: the windows of the focused workspace, the layout of
  the focused window, the config, pause and Settings. The right button and a ctrl-click do nothing. With
  VoiceOver, "pressing" the item (VO-space) opens the menu. To switch workspace: the key bindings or the CLI.
  The button never gets to see the mouse (a transparent view on top of it takes it), and the menu pops up
  below the item without highlighting it: no rounded background behind the item. A ⌘-drag still moves the
  item along the bar.
- The menu is **one card**, short on purpose, in the material of the menus of macOS: it follows light and dark
  mode by itself. At the top, *Inlay* and its state (*Tiling on*, *Paused* or *No permission*); in a binding
  mode other than `main`, the mode and the key that leaves it (*resize · esc*) take
  the place of the state. Then **the windows of the focused workspace**, by the name of their app and without
  icons, with a dot in the focused color of the palette on the focused one. They are only shown: a click on them
  does nothing. Then **the focused window**: a selector *Tiling · Floating · Fullscreen*. It runs the commands of
  the key bindings (`fullscreen` toggles, like `cmd-alt-ctrl-enter`), once the menu is closed; *Fullscreen* tiles
  a floating window first, so that a window alone in its workspace stays without gaps nor border with
  `gaps.smart`, like with the key binding. Then a row of four buttons for what concerns Inlay itself (*Reload*,
  *Config* that opens inlay.toml, *Pause/Resume* and *Settings*), the version (a click copies it, with the
  commit) and *Quit*. Switching workspaces, moving a window, balancing the sizes (`cmd-alt-comma`) and the binding
  modes are done with the key bindings. The theme and
  the palette are in the **Themes** page of Settings. **The menu does not show the key bindings of your
  config**. Its own shortcuts (⌘R, ⌘E, ⌘, and ⌘Q) only exist while it is open. When the last load of the config
  had errors or warnings, a block at the top says so, shows the first ones, and has *Config* and *Details*.
- The shipped config defines **7 persistent workspaces** (1–7), which are the ones the item always shows.
  7 is the empty one: no rule sends an app to it, so there is (almost) always a free workspace, on the main
  display (`cmd-alt-ctrl-7`, and `cmd-alt-shift-7` to move a window there). Any
  other workspace exists (and appears in the item) while it has windows or is the visible one.
- **Settings…** (⌘, in the menu, or opening Inlay again from Applications) edits those keys **in your config
  file**, line by line and without touching comments or the rest of the file, and reloads the config. If the
  config folder or the file is a symbolic link, the file is written where it really lives and the link stays. If you have no config yet, the first change creates
  `~/.config/inlay/inlay.toml` from the shipped one. A key written with dots (`inner.horizontal = 8` in
  `[gaps]`, `menu-bar.theme = …`) is edited in place, and a missing key of such a table is added with dots
  too, after the others. A key inside an inline table, or a gap per monitor (`[{ monitor.main = 16 }, 8]`), is
  not edited from Settings: its control appears disabled. A subtable that does not exist yet
  (`[menu-bar.colors]`, `[borders.mode-colors]`) is added right after its parent table.

### The Settings window

A sidebar, like the one of System Settings, with eight pages: **General** and **Themes**; *Windows*: **Tiling**,
**Gaps**, **Borders** and **Animations**; *Workflow*: **Workspaces** and **Shortcuts**.

- **Search**: the field at the top of the sidebar finds a setting by its title, by its key (`corner-radius`) or by
  its page. A click on a result opens its page and highlights the row for a moment.
- **The keys of the config**: a row shows the key it writes while the mouse is over it, or while ⌥ is held,
  over the row next to its control: nothing in the row moves. A click on the key copies its line (`width = 4`).
  *Show the config keys* (General, `[settings] show-keys`) shows them in every row all the time.
- **One height for every page**: the window doesn't change its size from page to page or between the parts of
  Themes; a taller page scrolls. The palettes show two rows at a time, and scroll inside of their section.
- **Undo**: the bottom of the sidebar shows the last change written (`[borders] width: 4 → 6`), with *Undo* and
  *Redo*, also ⌘Z and ⇧⌘Z (not while a text field is being edited, which has its own). Undoing writes back the
  text the file had, comments included; if the file changed since, by hand or by another program, nothing is
  undone and the window says why.
- **The sliders** have no tick marks: a small mark under the track tells the default, and the field next to them
  takes an exact value, with arrows for a step up or down.
- **Export complete config** (General › Configuration) saves a copy of your config, with your comments, plus every
  key that it leaves out with the value that applies (from the window and from the shipped config): a config with
  nothing implicit. Your file isn't touched. The key bindings and the window rules aren't added: they are yours.
- **General** also has the notice after a reload (`[notifications] on-reload`) and the switch of the menu bar item
  (`[menu-bar] enabled`), which had a tab of its own. **Tiling** has the split ratio (`[tiling] split-ratio`).
- **Workspaces**: a row per workspace, in the order of their names (making one persistent doesn't move it), with
  the apps that the `on-window-detected` rules send to it (read only: the rules are edited in the file), the key
  bindings that go to it and that move a window to it, and a switch that adds it to `persistent-workspaces` or
  removes it. Below, the apps that a rule makes floating.
- **Shortcuts**: the key bindings of the config, mode by mode, in the order of the file, with the comment written
  after each one and a filter. Read only.
- **Mode colors** (Borders): a mode without a color shows the active color it uses, striped, and *Set Color…*; one
  with a color has its picker and *Remove*.

These are the pages with the shipped config (click one to see it at full size):

<table>
<tr>
<td valign="top"><a href="docs/images/settings-general.png"><img src="docs/images/settings-general.png" alt="Real render of the General tab of Settings: Open at login (start-at-login); Configuration, with the path of the file, Show in Finder and Open, Reload on save (auto-reload-config) and the status of the last load; and Permissions, with 'Accessibility: granted'" width="280"></a></td>
<td valign="top"><a href="docs/images/settings-themes.png"><img src="docs/images/settings-themes.png" alt="Real render of the Themes tab of Settings: the live preview of the menu bar item and of three windows with their borders, next to a card that says which theme gives the colors; a segmented control with Palette, Indicator and Colors; and the Palette part: Made for You (System, Material · Wallpaper, Material · Color) and the other thirteen palettes in a compact grid of six columns" width="280"></a></td>
<td valign="top"><a href="docs/images/settings-tiling.png"><img src="docs/images/settings-tiling.png" alt="Real render of the Tiling tab of Settings: New Windows, with Placement (Dwindle or After Focused) and Window to split (Focused or Cursor); and Arrangement, with Windows already open (Grid, Row or Dwindle) and a Minimum window size slider at 100 pt" width="280"></a></td>
</tr>
<tr><td align="center"><sub>General</sub></td><td align="center"><sub>Themes</sub></td><td align="center"><sub>Tiling</sub></td></tr>
<tr>
<td valign="top"><a href="docs/images/settings-gaps.png"><img src="docs/images/settings-gaps.png" alt="Real render of the Gaps tab of Settings: a preview of three tiled windows with the gaps at their actual size and the borders of the Borders tab, then the sliders of the inner gaps (horizontal and vertical) and of the outer gaps (top, bottom, left and right), all at 8 pt" width="280"></a></td>
<td valign="top"><a href="docs/images/settings-animations.png"><img src="docs/images/settings-animations.png" alt="Real render of the Animations tab of Settings: Windows, with Animate the windows ([animations] enabled) and a Duration slider at 180 ms; and Workspaces, with Switching workspaces (Horizontal, Vertical, Auto or Off: [animations] workspace-switch)" width="280"></a></td>
<td valign="top"><a href="docs/images/settings-borders.png"><img src="docs/images/settings-borders.png" alt="Real render of the Borders page of Settings: a preview of an active, an inactive and a floating window with their borders, the Show borders switch, the Width slider with its field, the Square corners switch, the Corner radius slider, the Glow switch and the Glow radius slider, Hide with a single window, a note that the colors are in Themes, and a row per binding mode (resize and service) that uses the active color, with Set Color…" width="280"></a></td>
</tr>
<tr><td align="center"><sub>Gaps</sub></td><td align="center"><sub>Animations</sub></td><td align="center"><sub>Borders</sub></td></tr>
<tr>
<td valign="top"><a href="docs/images/settings-workspaces.png"><img src="docs/images/settings-workspaces.png" alt="Real render of the Workspaces page of Settings: a row per workspace from 1 to 7 with the apps that the rules send to it, its two key bindings and a switch for persistent-workspaces, then the floating apps" width="280"></a></td>
<td valign="top"><a href="docs/images/settings-shortcuts.png"><img src="docs/images/settings-shortcuts.png" alt="Real render of the Shortcuts page of Settings: a selector of the binding modes (main, service, resize), a filter, and the key bindings of main with their commands and comments" width="280"></a></td>
<td valign="top"><a href="docs/images/settings-window-themes.png"><img src="docs/images/settings-window-themes.png" alt="Real render of the whole Settings window on the Themes page: the sidebar with the search field and the eight pages, and the palettes as miniatures" width="280"></a></td>
</tr>
<tr><td align="center"><sub>Workspaces</sub></td><td align="center"><sub>Shortcuts</sub></td><td align="center"><sub>The window</sub></td></tr>
</table>

<sub>Real renders, drawn off screen by `Inlay --render-settings` (see [Development](#development)): the content
of each page, and the last one the whole window with its sidebar, without the title bar.</sub>

The window is never taller than the usable part of the screen and never leaves it. A page that does not fit
(on the screen of a small laptop, Borders is taller than what the menu bar and the Dock leave) scrolls, so
every control can be reached. `Inlay --debug-settings <config> [--inspect] [--screen-height <points>]` opens
the window alone, without the window manager, against a config file of your choice.

How the window and the file follow each other is in [Configuration](#configuration).

## Window borders

Inlay draws a colored border around each managed window (tiled or floating) of the visible workspaces. The
color comes from the state the manager already knows, with no focus heuristics. It is configured in the
`[borders]` table (`inlay config --explain borders` documents it), or in the **Borders** tab of Settings (its three
colors, in **Themes › Colors**).

<p align="center"><img src="docs/images/borders-states.png" alt="Real render of the window borders in six cases, around the windows of a sample desktop. The focused window with an orange border (active-color) and the others with a gray one (inactive-color); a focused floating window with a purple border (floating-color); the focused window with a green border in the resize mode, from [borders.mode-colors]; only the focused window with a border, with inactive-color = '#00000000'; a focused dialog without a border, and no window with the active color; and a fullscreen window with its border, drawn just inside of the screen" width="880"></p>

| Key | Values | Default |
|---|---|---|
| `enabled` | `true`, `false` | `true` |
| `width` | 1 … 20 (points) | `4` |
| `corner-radius` | 0 … 40 (points) | `16` |
| `square-corners` | `true`, `false` | `true` |
| `active-color` | color | `'system-accent'` |
| `inactive-color` | color | `'#8E8E9373'` |
| `floating-color` | color | `'#BF5AF2'` |
| `glow` | `true`, `false` | `false` |
| `glow-radius` | 1 … 40 (points) | `12` |
| `hide-when-single` | `true`, `false` | `false` |
| `[borders.mode-colors]` `<mode>` | color | empty table |

**The colors.** The image above shows them all.

```toml
[borders]
    enabled = true
    active-color = 'system-accent'   # the focused window, if it is tiled
    inactive-color = '#8E8E9373'     # the windows that are not focused. '#00000000': no border
    floating-color = '#BF5AF2'       # the focused window, if it is floating

    [borders.mode-colors]            # the focused window while a binding mode is active
        resize = '#30D158'
```

**`width`**: the thickness, outside of the window.

```toml
[borders]
    width = 4   # 1 ... 20 points
```

<p align="center"><img src="docs/images/borders-width.png" alt="Real render, detail of the gap between two windows with width = 2, width = 4 (the default) and width = 8: the border of the focused window, orange, and the one of its neighbor, gray, get thicker and take more of the gap" width="880"></p>

**`corner-radius`**: tuned by eye, because macOS does not let Inlay read the radius of the windows of other apps.

```toml
[borders]
    corner-radius = 16   # 0 ... 40 points. The radius of the corners of the windows
```

<p align="center"><img src="docs/images/borders-corner-radius.png" alt="Real render, detail of the corner of two neighboring windows with corner-radius = 0 (square corners), 8, 16 (the default) and 24" width="880"></p>

**`square-corners`**: the windows of macOS have rounded corners, and Inlay can't change them (that would need
System Integrity Protection disabled). What it can do is fill them: the outer edge of the border is square, and
its inner edge follows the corners of the window, so the corners that the window leaves empty take the color of
the border and the window looks square. It applies to every window with a border: focused, not focused and
floating.

```toml
[borders]
    square-corners = true   # false: the border follows the rounded corners of the windows
    corner-radius = 16      # the radius of the windows, or a bit more
```

Keep `corner-radius` at the radius of the windows or a bit above it: with less, a bit of what is behind the
window shows in its corners. A border with a translucent color, like the default `inactive-color`, fills the
corners with that same translucent color, and a window without a border keeps its round corners. The shadow of
the window, which macOS draws, stays round.

**`glow` and `glow-radius`**: a halo around the focused window.

```toml
[borders]
    glow = true
    glow-radius = 12   # 1 ... 40 points
```

<p align="center"><img src="docs/images/borders-glow.png" alt="Real render, detail of the border of the focused window with glow = false, and with glow = true and glow-radius = 6, 12 (the default) and 24: an orange halo outside of the border that reaches farther as the radius grows, over the gap and the edge of the neighboring window" width="880"></p>

**`hide-when-single`**: no border around the tiling window of a workspace that has only one, fullscreen or not:
there is no other window to tell it from. The border comes back as soon as a second tiling window joins it.
Floating windows keep theirs. It is for a single window that keeps the outer gaps: [smart gaps](#gaps) already
remove the border along with the gaps. It is also in **Settings › Borders**.

```toml
[borders]
    hide-when-single = true
```

**Borders and gaps**: the border takes a part of the [gap](#gaps).

```toml
[gaps]
    inner.horizontal = 8   # at least twice borders.width leaves air between two borders
[borders]
    width = 2
```

<p align="center"><img src="docs/images/borders-gaps.png" alt="Real render, detail of the gap between two windows: with gaps of 8 and width = 4, the values of the shipped config, the two borders touch; with gaps of 8 and width = 2 there are 4 points of air between them; with gaps of 14 and width = 4, 6 points" width="880"></p>

The details:

- **Color of the focused window**: the one of the active binding mode if it has an entry in
  `[borders.mode-colors]`; otherwise, `floating-color` if it is floating; otherwise, `active-color`. The other
  windows use `inactive-color`.
- A **fully transparent** color (`'#00000000'`) means "no border": with
  `inactive-color = '#00000000'` only the active window has a border.
- A **fullscreen** window (the `fullscreen` command) keeps its border. Where the outer gaps leave no room for
  it, as with `fullscreen --no-outer-gaps`, it is drawn just inside of the screen.
- **No border**: windows in the native fullscreen of macOS, the tiled windows that a fullscreen window covers,
  minimized windows, windows of hidden apps, popups, the ones of non-visible workspaces, and the window you are
  dragging or resizing with the mouse (the border comes back on release).
- **Dialogs and sheets, no border**: only normal windows, tiled or floating, have a border. What Inlay
  detects as a dialog (the same AeroSpace heuristics that decide which window becomes floating on its own:
  open and save panels, sheets, windows without a fullscreen button…) has no border. A normal window that you
  make floating (`layout floating`, or an `on-window-detected` rule) does have one. If you turn a dialog into
  a tiled window it has a border while it is tiled. With a dialog focused, no window has the color of the
  active one.
- The border goes **outside** the window frame, in the gap between windows: it does not cover content and does
  not receive clicks. The `gaps` should be at least twice the `width`; with smaller gaps the borders of two
  neighboring windows touch or overlap. The shipped config has gaps of 8 and the default border of 4, so
  neighboring borders touch: lower `width` to 2 or 3, or raise the gaps, to leave air between them.
- **Glow** (`glow = true`): a glow in the color of the border around the **focused** window (with whatever
  color applies to it: active, floating or mode), which fades outwards over about `glow-radius` points.
  Unfocused windows never have it. It is exterior: it is not drawn under the border or over the window, but it
  is drawn over whatever is around it (the gap and, if it is wider than the gap, the edge of the neighboring
  windows). It does not receive clicks. It is a small image that Core Animation stretches, so moving or resizing
  redraws nothing.
- The corner radius is fixed: macOS does not let you read the one of other apps' windows. Adjust it by eye.
- The borders disappear when Inlay is paused (`inlay enable off`), on quit and with `enabled = false`.
- **Colors per mode in Settings**: the **Borders** page has a row for each binding mode defined in your
  config (`[mode.<name>.binding]`). A mode without a color shows the active color it uses and *Set Color…*, which
  starts from it; a mode with one has a color picker and *Remove*, which deletes the key from
  `[borders.mode-colors]`. If the table does not exist it is created right after `[borders]`. The `main` mode
  has no row: it is the mode that is always active, and a color of its own would replace `active-color` and
  `floating-color` for good, which exist for that purpose (you can still write `main = '…'` by hand).

Each border is a window of Inlay's own, transparent, placed right above its window in the stacking order, so
a floating window of another app covers the borders of the windows behind it. All with public AppKit API;
there is no JankyBorders code and SkyLight is not used.

## Troubleshooting

Inlay only works when something happens (a window appears, the focus changes, a key binding runs): at rest it
uses about 0 % of the CPU. If it keeps using CPU with nothing going on, two commands tell what it is busy with:

```sh
inlay debug-stats --watch 5               # counters of what Inlay does, printed every 5 s (ctrl-c to stop)
sample Inlay 5 -file ~/inlay-sample.txt   # where the CPU time goes (it comes with macOS)
```

`inlay debug-stats` prints, for every counter, the total since Inlay started and what was counted since the
previous call (`new`, and `per-sec`). It only reads counters that Inlay keeps in memory, and the server answers
it without refreshing anything, so asking does not change the numbers. Leave the Mac alone while it runs: at
rest every `per-sec` should be 0. The one that is not tells what is going on:

| Counter | What it counts |
|---|---|
| `session.complete.*`, `session.light.*` | Refresh sessions: Inlay asks every app for its windows and lays them out |
| `session.trigger.*` | What started each session: `ax.AXMoved` (a window moved), `workspace.NSWorkspaceDidActivateApplicationNotification`, `hotkey`, `cli.<command>`... |
| `ui.publish` | Times the menu bar, the borders and Settings were told that something may have changed |
| `menu-bar.snapshot.changed` / `.same` | Whether that changed what the menu bar item shows |
| `menu-bar.draw.request.*` | Who asked to draw the item: `appearance` (the menu bar behind it), `system-colors`, `screens` |
| `menu-bar.draw.drawn` / `.skipped-same` | Images really drawn, and requests that needed none |
| `borders.op.*`, `borders.restack.*`, `borders.settle` | Borders created, moved, recolored, removed and reordered, and the checks that follow a refresh |
| `config.watcher.*`, `config.load` | Events of the config file watcher, and loads of the config |

## Uninstallation

```sh
inlay uninstall           # pick what to remove in a list, see what is removed and what is kept, confirm
inlay uninstall --purge   # everything starts checked in the list (but the Accessibility entry)
inlay uninstall --yes     # no questions: the app, the CLI link, the login item and your config
```

<p align="center"><img src="docs/images/terminal-uninstall.png" alt="Real output of 'inlay uninstall' in a terminal: a list of checkboxes with the app, the CLI link, the config (checked here) and the Accessibility entry; then what is removed (the app, the CLI link and ~/.config/inlay, a symbolic link of which only the link goes), what is kept (~/.dotfiles/inlay) and what is never touched; it asks for confirmation, gets 'y', removes them and says how to go back to AeroSpace" width="880"></p>

First it asks **what to remove**, in a list of checkboxes (Space checks and unchecks, `a` all of them, Enter is
done): the app and its login item, the CLI link, your config, the config backups of `install.sh`, the
preferences and runtime files of the app, and its Accessibility entry. Only what exists is listed. **The app
and the CLI link start checked; your config does not**: check it to remove it. With `--purge` everything starts
checked but the Accessibility entry. Then it lists, in three groups, what is **removed** (with the size of the
app), what is **kept** (including what a removed link points to) and what it **never touches** (the signing
identity, and the Accessibility entry if it is not checked, each with how to remove it by hand), and asks
`Remove what is listed under Removed? [y/N]`. Without a terminal that shows colors the list is one question per
line.

`--yes` skips both questions (and is required when there is no terminal to answer on): it removes the app, the
CLI link, the login item and your config, and with `--purge` the preferences, the runtime files and the config
backups too. It works whether Inlay is running or not: a running Inlay is quit
first, and on quit it brings the windows of the non-visible workspaces back to the screen. The command
removes the app that contains it, so it runs from a temporary copy of the uninstall script, which deletes
itself at the end.

It removes the app that the `inlay` you ran belongs to, and the copies in `/Applications` and in
`~/Applications`; with `INSTALL_DIR=…` it looks in that folder instead of those two.

Your config is `~/.config/inlay` and `~/.inlay.toml`. When it is removed:

- a real folder or file is **saved first in `~/inlay-config-<date>.tar.gz`**, and then deleted;
- `~/.config/inlay` is a **symbolic link** to a folder of yours: **only the link is removed**. The folder it
  points to and its `inlay.toml` are never touched, and the list names that folder as kept;
- a link inside of a real `~/.config/inlay` (an `inlay.toml` linked by a previous version) goes with the
  folder; the file it points to is never touched.

The config backups are the ones that `install.sh` made outside of the config folder
(`~/.config/inlay.backup-<date>`, `~/.inlay.toml.backup-<date>`; a backup that is a link is removed as a link).

`./uninstall.sh` in the repo does the same (it is the same script, with the same options), for when the CLI
is not at hand.

It touches nothing of AeroSpace, AeroMenu or `borders`: to go back to them, open AeroSpace and AeroMenu and run
`brew services start borders`.

The Accessibility entry is only removed when it is checked (`tccutil reset Accessibility
com.davidhiguita.inlay`). The signing identity is never removed: delete it in *Keychain Access* if you want.

## Development

```sh
scripts/build-app.sh    # builds and leaves a signed build/Inlay.app (installs nothing)
scripts/test.sh         # runs the tests (accepts the arguments of 'swift test', e.g. --filter DwindleTest)
scripts/make-icon.sh    # regenerates Support/AppIcon.icns from scripts/icon/AppIcon.swift
scripts/make-docs-images.sh   # regenerates the images of this page in docs/images
```

To see the menu bar item without starting Inlay, `--render-menu-bar` draws it off screen (each theme, on a
dark and a light bar, with default and custom colors; `_sheet.png` gathers them all) and exits:

```sh
build/Inlay.app/Contents/MacOS/Inlay --render-menu-bar /tmp/inlay-item
build/Inlay.app/Contents/MacOS/Inlay --render-menu-bar /tmp/inlay-item-6x 6   # enlarged: 6 pixels per point
build/Inlay.app/Contents/MacOS/Inlay --render-settings /tmp/inlay-settings     # the Settings tabs, as PNG
INLAY_RENDER_DIR=/tmp/inlay-item scripts/test.sh --filter SettingsModelTest   # the same tabs, from the tests
```

`--render-settings <dir> [<config>]` draws the tabs as they are with the shipped config, or with the config file
given; it neither reads nor writes your config, and only shows the path a new config would get.

The Settings window can also be opened for real, alone: `--debug-settings <config>` shows it without the
window manager, the menu bar item, the key bindings or the Accessibility permission, editing the config file
you give it (nothing is reloaded), and exits when the window is closed. With `--inspect` it does not wait: it
shows every tab, prints where each control ended up and whether a click reaches it (scrolling to it if it takes
that), and exits with an error if something can't be reached. `--screen-height <points>` makes the window
behave as on a screen that leaves that much height.

```sh
cp inlay.toml /tmp/inlay-test.toml
build/Inlay.app/Contents/MacOS/Inlay --debug-settings /tmp/inlay-test.toml
build/Inlay.app/Contents/MacOS/Inlay --debug-settings /tmp/inlay-test.toml --inspect --screen-height 700
```

The same goes for the borders. `--render-borders` draws them off screen in each state, and `--debug-borders`
shows them for real for a few seconds around the windows that are on screen (without moving anything and
without the Accessibility permission), prints how they ended up stacked and removes them:

```sh
build/Inlay.app/Contents/MacOS/Inlay --render-borders /tmp/inlay-borders
build/Inlay.app/Contents/MacOS/Inlay --debug-borders 5
```

The scripts force `DEVELOPER_DIR=/Library/Developer/CommandLineTools` even if `xcode-select` points to Xcode,
to guarantee that the project does not depend on it. To build by hand:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift test
```

The tests use Swift Testing (XCTest does not come with the Command Line Tools, and no XCTest target is left).
All the suites are nested in `InlayTests` (`extension InlayTests { @Suite @MainActor struct FooTest { ... } }`),
which is `.serialized`: the tests share the global model and cannot run in parallel.

**The images of this page** are made by `scripts/make-docs-images.sh` from the sources in
[`docs/images/src`](./docs/images/src): the real renders come from the three `--render-*` options above; the
sheets that gather them and the illustrations are HTML pages that a headless Google Chrome turns into PNG files;
and the animations are HTML pages too, whose frames `docs/images/src/gif.swift` (built with the Command Line
Tools) assembles into GIF files. Nothing is installed, and Inlay is not started. The renders show the accent
color of the Mac they are made on, and the illustrations use generic windows: no icons and no names of real apps. `scripts/make-docs-images.sh hero gaps`
regenerates only those images, and `--no-build` skips the build of `build/Inlay.app`.

To find out what Inlay would say about any config file without installing or starting anything (errors and
warnings of the real parser):

```sh
build/Inlay.app/Contents/MacOS/Inlay --check-config ~/.aerospace.toml
```

| Path | Contents |
|---|---|
| `Sources/InlayApp` | Entry point of the app (the `InlayApp` product, which in the bundle is `Contents/MacOS/Inlay`) |
| `Sources/AppBundle` | The window manager: tree, commands, configuration, server, interface |
| `Sources/Cli` | The `inlay` CLI (client of the `/tmp/com.davidhiguita.inlay-$USER.sock` socket) |
| `Sources/Common` | Code shared by the app and the CLI |
| `Sources/BuildInfo` | Version and git hash, which `build-app.sh` passes through environment variables |
| `Sources/PrivateApi` | Header of `_AXUIElementGetWindow` |
| `inlay.toml` | The shipped config: what `install.sh` copies and what the app falls back to |
| `docs` | `config-reference.toml` (every config key, printed by `inlay config --explain`), an i3-like example config, a copy of the AeroSpace documentation, and `images` (the images of this page, with their sources in `images/src`) |
| `Tests/InlayTests` | Tests with Swift Testing. `support/` holds the fake windows and other utilities; `fixtures/`, example configs |
| `Support` | `Info.plist` and the bundle icon |
| `scripts` | Build, tests, install, uninstall, icon and the images of the README. `uninstall.sh` and `lib.sh` also travel inside the app, for `inlay uninstall` |
| `axDumps` | Accessibility dumps of real apps used by the tests |

Things to keep in mind:

- **Do not use SwiftUI's `@State`** (or `#Preview`): in the macOS 27 SDK they are macros whose plugin only
  comes with Xcode. Use `@StateObject`/`ObservableObject`, `@Observable` + `@Bindable`, or AppKit.
- The version is in the [`VERSION`](./VERSION) file.

## Attribution and license

Inlay is distributed under the MIT license ([LICENSE](./LICENSE)).

- It derives from **[AeroSpace](https://github.com/nikitabobko/AeroSpace)** by Nikita Bobko (MIT), commit
  `74a1bf1`: the window manager, the config format, the commands and the CLI come from there. Its copyright
  notice is kept. Inlay is not affiliated with the AeroSpace project: please do not report Inlay bugs there.
- The build without Xcode and the install scripts follow the ones of **Aeromenu**, by the same author as Inlay.
- It contains **no** JankyBorders code (GPL-3.0).

The details, with the bundled dependencies and their licenses, are in [NOTICE.md](./NOTICE.md).
