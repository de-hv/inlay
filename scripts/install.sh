#!/usr/bin/env bash
#
# Builds Inlay, installs it and opens it. Needs only the Xcode Command Line Tools: no Xcode, no Apple ID.
# No option is needed:
#
#   ./install.sh
#
# What it does:
#   - builds Inlay.app and signs it with a local identity, so that macOS keeps the Accessibility permission
#     across rebuilds (see "Signing" below);
#   - installs it into /Applications (or ~/Applications if /Applications isn't writable);
#   - links the 'inlay' CLI into ~/.local/bin, /opt/homebrew/bin or /usr/local/bin;
#   - creates ~/.config/inlay/inlay.toml from the inlay.toml of the repo if you have no Inlay config yet
#     (what happens to a config that you already have: see "Your config" below);
#   - asks, every time, whether you want to use a config folder of your own through a symbolic link
#     (see "Your own config folder" below). Enter keeps what you have;
#   - opens Inlay and tells you what to do the first time (the Accessibility permission).
# Running it again updates the installed app: the running copy is quit first.
#
# Your config: a config that you already have is yours, and it is never edited, replaced or deleted. With one
# exception: a config that is identical, byte for byte, to a default config that a previous version of Inlay
# installed (scripts/default-config-hashes.txt) was never edited by anybody, so it is replaced by the current
# inlay.toml, and the old one is kept next to it as inlay.toml.backup-<date>. Any other config is kept as it
# is, and the script says so: what is new in the inlay.toml of the repo is not in it. --reset-config is how
# you switch to the config of the repo on purpose.
#
# Your own config folder: if you answer yes to the question, you give the path of a folder (~/.dotfiles/inlay,
# for example) and ~/.config/inlay becomes a symbolic link to that folder. Inlay reads and writes the inlay.toml
# in it; nothing else of the folder is touched.
#   - The script lists the folders of a dotfiles repo that it finds (~/.dotfiles/inlay, ~/dotfiles/inlay…):
#     type the number of one, or a path (Tab completes it).
#   - The folder doesn't exist, or it can't be linked: the script says why and asks again. Enter with nothing
#     keeps your config as it is. With --config-link, nothing is linked.
#   - The folder has no inlay.toml: the script asks whether to copy the inlay.toml of the repo into it. If you
#     say no, it asks for another folder (with --config-link, nothing is linked).
#   - You already had a real ~/.config/inlay: it is not deleted. It is renamed to ~/.config/inlay.backup-<date>.
#   - ~/.config/inlay already is a link: the question says where it points, and Enter leaves it alone.
#     Linking another folder only replaces the link: the folder it pointed to is not touched.
#   - A previous version linked the file instead (~/.config/inlay/inlay.toml -> your file). It still works and
#     it is left alone; answer yes to link the folder that holds that file instead.
# A linked folder is yours: its inlay.toml is never replaced on its own, not even when it is identical to an
# old default config.
#
# Options (none of them is needed):
#   --config-link <folder> link ~/.config/inlay to <folder> without asking, with the same rules as above. A
#                          folder without inlay.toml is only filled in if there is a terminal to ask on
#   --no-prompt            don't ask anything: keep the config as it is. It's what happens on its own when
#                          there is no terminal to ask on
#   --reset-config         replace your config by the inlay.toml of the repo, whatever is in it. Your config is
#                          kept next to it as inlay.toml.backup-<date>. Nothing that a symbolic link points to
#                          is ever written, moved or deleted: with a linked folder, the link itself is renamed
#                          to ~/.config/inlay.backup-<date> and ~/.config/inlay becomes a real folder with the
#                          inlay.toml of the repo; with a linked file, the link becomes the backup
#   --import-aerospace     start from your AeroSpace config (~/.aerospace.toml) instead of inlay.toml
#   --no-open              don't open Inlay when done
#   --adhoc-signing        sign ad hoc instead of with the local identity
#   INSTALL_DIR=~/Applications ./install.sh    where to install the app
#   INLAY_BIN_DIR=~/bin ./install.sh           where to link the 'inlay' CLI
#
# Signing: macOS ties the Accessibility permission to the signature of the app. So the app is signed with a
# self-signed code signing identity ("Inlay Local Code Signing") that is created, once, in your login keychain:
# the permission survives the rebuilds. macOS may ask for your keychain password the first time codesign uses
# the key: choose "Always Allow". If the identity can't be created or used, the app is signed ad hoc, with a
# warning: with an ad hoc signature the permission is lost on every rebuild. --adhoc-signing skips the identity.
# (--stable-signing is still accepted: it's the default.)
#
# AeroSpace, AeroMenu and borders (JankyBorders) do the same job as Inlay. This script never quits them: if one
# is running it tells you, and leaves Inlay closed until you quit them yourself.

set -euo pipefail

usage() { sed -n '3,68s/^# \{0,1\}//p' "$SCRIPT_PATH"; }

check_requirements() {
  local macos swift
  macos="$(sw_vers -productVersion)"
  version_at_least "$macos" 14 0 || fail "Inlay needs macOS 14 or later. This Mac runs macOS $macos."
  use_command_line_tools
  swift="$(swift_version)"
  [ -n "$swift" ] || fail "could not tell the Swift version ('swift --version' failed)."
  version_at_least "$swift" 6 2 ||
    fail "Inlay needs Swift 6.2 or later. The Command Line Tools have Swift $swift: update them in Software Update."
  command -v codesign >/dev/null 2>&1 || fail "codesign was not found."
  info "Requirements" "macOS $macos · Swift $swift (${DEVELOPER_DIR:-selected toolchain})"
}

# Sets INSTALL_TARGET
choose_install_dir() {
  local dir
  if [ -n "${INSTALL_DIR:-}" ]; then
    dir="$INSTALL_DIR"
    mkdir -p "$dir" 2>/dev/null || true
    [ -d "$dir" ] && [ -w "$dir" ] || fail "$dir is not a writable directory."
  elif [ -w /Applications ]; then
    dir="/Applications"
  else
    dir="$HOME/Applications"
    mkdir -p "$dir"
    note "/Applications is not writable: installing into $dir instead."
  fi
  INSTALL_TARGET="$dir/$APP_NAME.app"
}

# Sets CONFLICTS to the names of the running apps that would fight with Inlay
find_conflicts() {
  local name
  CONFLICTS=""
  for name in AeroSpace AeroSpace-Debug AeroMenu borders; do
    if pgrep -x "$name" >/dev/null 2>&1; then
      CONFLICTS="$CONFLICTS $name"
    fi
  done
  CONFLICTS="${CONFLICTS# }"
}

# build_app <stable|adhoc>. Sets SIGNED_WITH to 'stable' or 'adhoc': the signature that the build really got
build_app() {
  local mode="$1" signature
  if [ "$mode" = stable ]; then
    note "Signing with a stable identity. macOS may ask for your keychain password: choose \"Always Allow\"."
    if ensure_signing_identity; then
      scripts/build-app.sh --sign-identity "$SIGN_IDENTITY_NAME"
    else
      warn "falling back to an ad hoc signature: the Accessibility permission will be lost on every rebuild."
      mode=adhoc
    fi
  fi
  if [ "$mode" = adhoc ]; then
    scripts/build-app.sh --sign-identity -
  fi
  # build-app.sh falls back to an ad hoc signature on its own when codesign can't use the identity.
  # Not a pipe into 'grep -q': with pipefail, grep leaving early makes the pipe fail
  signature="$(codesign --display --verbose "build/$APP_NAME.app" 2>&1 || true)"
  case "$signature" in
    *Signature=adhoc*) SIGNED_WITH=adhoc ;;
    *) SIGNED_WITH=stable ;;
  esac
}

install_app() {
  quit_running_inlay
  echo
  info "Installing"
  rm -rf "$INSTALL_TARGET"
  ditto "build/$APP_NAME.app" "$INSTALL_TARGET"
  # Tells Finder and Launch Services that the bundle changed
  touch "$INSTALL_TARGET"
  "$LSREGISTER" -f "$INSTALL_TARGET" >/dev/null 2>&1 || true
  ok "Installed $(pretty_path "$INSTALL_TARGET")"
}

link_cli() {
  local dir="" candidate link source="$INSTALL_TARGET/$CLI_PATH_IN_APP"
  if [ -n "${INLAY_BIN_DIR:-}" ]; then
    dir="$INLAY_BIN_DIR"
    mkdir -p "$dir" 2>/dev/null || true
    [ -d "$dir" ] && [ -w "$dir" ] || { warn "$dir is not writable: the '$CLI_NAME' CLI was not linked."; return 0; }
  else
    # Prefer a directory that already is in the PATH
    while IFS= read -r candidate; do
      if [ -d "$candidate" ] && [ -w "$candidate" ] && dir_is_in_path "$candidate"; then
        dir="$candidate"
        break
      fi
    done <<LIST
$(cli_dir_candidates)
LIST
    if [ -z "$dir" ]; then
      dir="$HOME/.local/bin"
      mkdir -p "$dir"
    fi
  fi

  link="$dir/$CLI_NAME"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    warn "$link exists and is not a symlink: leaving it alone. The CLI is at $source"
    return 0
  fi
  ln -sfn "$source" "$link"
  ok "Linked the CLI: $(pretty_path "$link") ${C_MAGENTA}->${C_RESET} $(pretty_path "$source")"
  if ! dir_is_in_path "$dir"; then
    warn "$dir is not in your PATH. Add this line to ~/.zshrc:"
    warn "  export PATH=\"$dir:\$PATH\""
  fi
}

# Prints the path of the user's AeroSpace config, if there is one
aerospace_config() {
  local candidate
  for candidate in "$HOME/.aerospace.toml" "$(config_home)/aerospace/aerospace.toml"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Prints a name for the backup of <config> that isn't taken: <config>.backup-20261012-153000
backup_path() {
  local base n=1 candidate
  base="$1.backup-$(date +%Y%m%d-%H%M%S)"
  candidate="$base"
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    n=$((n + 1))
    candidate="$base-$n"
  done
  printf '%s\n' "$candidate"
}

path_exists() { [ -e "$1" ] || [ -L "$1" ]; }

# replace_config <config>. Puts the inlay.toml of the repo in the place of the config. The config is renamed, not
# copied: if it is a symbolic link, it is the link that becomes the backup, and the file it points to is never
# written, moved or deleted. Sets CONFIG_BACKUP
replace_config() {
  local config="$1"
  CONFIG_BACKUP="$(backup_path "$config")"
  mv "$config" "$CONFIG_BACKUP"
  cp inlay.toml "$config"
}

# kept_config_warning <config>. The config stays, and what is new in the repo is not in it
kept_config_warning() {
  local config="$1"
  warn "your config was KEPT as it is: it is not a default config of Inlay, so it is yours."
  warn "What is new in the inlay.toml of the repo (key bindings, rules, options) is NOT in it."
  if [ ! -e "$config" ]; then
    warn "It is a symbolic link to a file that doesn't exist: Inlay can't read it."
  elif ! grep -Eq '^[[:space:]]*\[\[on-window-detected\]\]' "$config"; then
    warn "It has no 'on-window-detected' rule: no window is sent to a workspace, they all stay in the"
    warn "workspace where they open."
  fi
  warn "To switch to the config of the repo (yours is kept, as a backup-<date> next to it):"
  warn "  ./install.sh --reset-config"
  warn "To compare them:  diff \"$config\" \"$PWD/inlay.toml\""
}

# existing_config <config> <reset: true|false>. What happens to a config file that is already there, in a real
# folder. See "Your config"
existing_config() {
  local config="$1" reset="$2" target=""
  if [ -L "$config" ]; then target="$(readlink "$config")"; fi

  if [ "$reset" = true ]; then
    replace_config "$config"
    ok "Replaced your config by the inlay.toml of the repo (--reset-config): $(pretty_path "$config")"
    if [ -n "$target" ]; then
      note "It was a symbolic link to $target"
      note "Only the link was replaced: that file was not touched. The link is kept as"
      note "$CONFIG_BACKUP"
    else
      note "Your previous config is kept as $CONFIG_BACKUP"
    fi
    return 0
  fi

  if [ -z "$target" ] && cmp -s "$config" inlay.toml; then
    ok "You already have a config: $(pretty_path "$config")"
    hint "It is the inlay.toml of the repo, as it is now. Nothing to do."
    return 0
  fi

  if [ -z "$target" ] && is_known_default_config "$config" scripts/default-config-hashes.txt; then
    replace_config "$config"
    ok "Updated your config to the inlay.toml of the repo: $(pretty_path "$config")"
    note "It was the default config of a previous version of Inlay, exactly as it was installed: nobody had"
    note "edited it. The previous one is kept as $CONFIG_BACKUP"
    return 0
  fi

  if [ -n "$target" ]; then
    ok "You already have a config: $(pretty_path "$config") ${C_MAGENTA}->${C_RESET} $(pretty_path "$target")"
  else
    ok "You already have a config: $(pretty_path "$config")"
  fi
  kept_config_warning "$config"
}

# linked_config_folder <config folder> <reset: true|false>. The config folder is a symbolic link to a folder of
# the user. Nothing in that folder is ever written, moved or deleted here: at most the link itself is renamed
linked_config_folder() {
  local dir="$1" reset="$2" target
  target="$(readlink "$dir")"

  if [ "$reset" = true ]; then
    CONFIG_BACKUP="$(backup_path "$dir")"
    mv "$dir" "$CONFIG_BACKUP"
    mkdir -p "$dir"
    cp inlay.toml "$dir/inlay.toml"
    ok "Replaced your config by the inlay.toml of the repo (--reset-config): $(pretty_path "$dir/inlay.toml")"
    note "$dir was a symbolic link to $target"
    note "Only the link was replaced: that folder and its files were not touched. The link is kept as"
    note "$CONFIG_BACKUP"
    note "$dir is a real folder now. To link your folder again: ./install.sh --config-link \"$target\""
    return 0
  fi

  ok "You already have a config: $(pretty_path "$dir") ${C_MAGENTA}->${C_RESET} $(pretty_path "$target") (a linked folder)"
  if [ ! -d "$dir" ]; then
    warn "the folder that $dir points to doesn't exist: Inlay can't read your config, and uses"
    warn "its built-in one until the folder is back."
  elif ! path_exists "$dir/inlay.toml"; then
    warn "$target has no inlay.toml: Inlay uses its built-in config until there is one."
  elif cmp -s "$dir/inlay.toml" inlay.toml; then
    hint "Its inlay.toml is the one of the repo, as it is now. Nothing to do."
  else
    kept_config_warning "$dir/inlay.toml"
  fi
}

# ensure_config <import aerospace: true|false> <link: a folder, or empty> <prompt: true|false> <reset: true|false>
# Creates the config when there is none. An existing one is only replaced when it is a default config of a
# previous version, or when --reset-config asks for it, and it is always kept as a backup. See "Your config".
# Then the config folder can become a symbolic link to a folder of the user. See "Your own config folder"
# Sets CONFIG_PATH to the config that Inlay will read, or to nothing if it can't tell (two configs)
ensure_config() {
  local import="$1" link="$2" prompt="$3" reset="$4" dir xdg dotfile source
  dir="$(config_home)/inlay"
  xdg="$dir/inlay.toml"
  dotfile="$HOME/.inlay.toml"
  CONFIG_PATH=""
  CONFIG_CREATED=false
  echo
  info "Your config"

  if path_exists "$dotfile"; then
    if path_exists "$xdg"; then
      warn "both $xdg and $dotfile exist: Inlay will report an ambiguous config until you remove one."
      if [ "$reset" = true ]; then
        warn "--reset-config was ignored: it can't tell which of the two is your config. Remove one and run it again."
      fi
    else
      CONFIG_PATH="$dotfile"
      existing_config "$dotfile" "$reset"
    fi
    if [ "$import" = true ]; then
      note "--import-aerospace was ignored: you already have an Inlay config."
    fi
    # Inlay reads either file, never both: a linked folder next to ~/.inlay.toml would be a second config
    if [ -n "$link" ]; then
      warn "--config-link was ignored: your config is $dotfile. To use a config folder, move that file"
      warn "into the folder as inlay.toml and run this script again."
    elif [ "$prompt" = true ] && is_interactive; then
      note "Your config is $dotfile: the question about a config folder of your own is skipped."
      note "(To use one, move that file into the folder as inlay.toml and run this script again.)"
    fi
    return 0
  fi

  if [ -L "$dir" ]; then
    CONFIG_PATH="$xdg"
    linked_config_folder "$dir" "$reset"
  elif path_exists "$xdg"; then
    CONFIG_PATH="$xdg"
    existing_config "$xdg" "$reset"
  else
    if [ "$reset" = true ]; then
      note "--reset-config: you have no Inlay config to replace. Creating it."
    fi
    # Remembered: a folder that this run has just created is not worth a backup when it gives way to a link
    if [ ! -d "$dir" ]; then CONFIG_CREATED=true; fi
    mkdir -p "$dir"
    CONFIG_PATH="$xdg"
    if [ "$import" = true ] && source="$(aerospace_config)"; then
      # cp follows a symlink, so the result is a regular file of your own
      cp "$source" "$xdg"
      ok "Created $(pretty_path "$xdg") from $(pretty_path "$source")"
      review_imported_config "$xdg"
    else
      if [ "$import" = true ]; then
        warn "--import-aerospace: no AeroSpace config found (~/.aerospace.toml). Using the default config."
      fi
      cp inlay.toml "$xdg"
      ok "Created $(pretty_path "$xdg") (a copy of the inlay.toml of the repo)"
    fi
    import=false
  fi
  if [ "$import" = true ]; then
    note "--import-aerospace was ignored: you already have an Inlay config."
  fi
  if [ "${XDG_CONFIG_HOME:-$HOME/.config}" != "$HOME/.config" ]; then
    note "XDG_CONFIG_HOME is set in this shell. Inlay only finds the config there if the variable is also set"
    note "for the apps that macOS starts (launchctl setenv). Otherwise it reads ~/.config/inlay/inlay.toml."
  fi

  link_config_folder "$dir" "$link" "$prompt"
}

# Says that nothing was linked, and which config is in effect
nothing_was_linked() {
  if [ "$CONFIG_CREATED" = true ]; then
    warn "Nothing was linked. The default config stays: $(pretty_path "$CONFIG_PATH") (a copy of the inlay.toml of the repo)."
  else
    warn "Nothing was linked. Your config stays as it is: $(pretty_path "$CONFIG_PATH")"
  fi
}

# Folders where people keep the config of Inlay in a dotfiles repo, the ones that exist. Prints one per line
config_folder_candidates() {
  local base sub
  for base in "$HOME/.dotfiles" "$HOME/dotfiles" "$HOME/.dots" "$HOME/dots" "$(config_home)/dotfiles"; do
    for sub in inlay .config/inlay config/inlay; do
      if [ -d "$base/$sub" ]; then printf '%s\n' "$base/$sub"; fi
    done
  done
  return 0
}

# check_link_target <config folder> <folder> <link now: a folder, or empty> <can ask: true|false>
# Whether the config folder can be linked to <folder>, saying why not. Returns 0 if it can, 1 if it can't and
# 2 if it already is. A folder without inlay.toml gets the one of the repo if the user says so
check_link_target() {
  local dir="$1" target="$2" current="$3" can_ask="$4" pretty
  pretty="$(pretty_path "$target")"
  if [ -f "$target" ]; then
    problem "$pretty is a file. The link is to the folder that holds your inlay.toml: $(pretty_path "$(dirname "$target")")"
    return 1
  fi
  if [ ! -d "$target" ]; then
    problem "$pretty is not an existing folder."
    return 1
  fi
  if [ -d "$dir" ] && [ "$target" -ef "$dir" ]; then
    if [ -n "$current" ]; then
      ok "$(pretty_path "$dir") is already linked to that folder. Nothing was changed."
      return 2
    fi
    problem "$pretty is the config folder itself: it can't be a link to itself."
    return 1
  fi
  if path_exists "$target/inlay.toml"; then
    return 0
  fi
  warn "$pretty has no inlay.toml."
  if [ "$can_ask" = true ]; then
    if ask_yes_no "Copy the inlay.toml of the repo into $pretty?"; then
      cp inlay.toml "$target/inlay.toml"
      ok "Copied the inlay.toml of the repo to $pretty/inlay.toml"
      return 0
    fi
    return 1
  fi
  warn "Nothing was copied into it: there is no terminal to ask on. Put an inlay.toml in that folder and"
  warn "run this script again."
  return 1
}

# choose_config_folder <config folder> <suggestion, or empty> <link now, or empty>
# Asks for the folder to link until it gets one that can be linked, or nothing. Lists the folders of a dotfiles
# repo that it finds, to pick one by its number. Sets CHOSEN_FOLDER. Returns 1 if nothing is to be linked
# and 2 if the config folder already is linked to the folder
choose_config_folder() {
  local dir="$1" suggestion="$2" current="$3" found="" candidate n=0 count default="" default_number="" answer target status
  local first=true
  CHOSEN_FOLDER=""
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    # Not the config folder itself, nor a folder already in the list
    if [ -d "$dir" ] && [ "$candidate" -ef "$dir" ] && [ -z "$current" ]; then continue; fi
    case "$(printf '\n%s\n' "$found")" in *$'\n'"$candidate"$'\n'*) continue ;; esac
    found="$found$candidate"$'\n'
  done <<LIST
$suggestion
$(config_folder_candidates)
LIST
  count="$(printf '%s' "$found" | grep -c . || true)"
  if [ "$count" -gt 0 ]; then
    hint "Found:"
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      n=$((n + 1))
      # Enter picks the first folder of the list, unless it is the one linked now: that would change nothing
      if [ -z "$default" ] && ! { [ -n "$current" ] && [ "$candidate" -ef "$dir" ]; }; then default_number="$n" default="$candidate"; fi
      if [ -n "$current" ] && [ "$candidate" -ef "$dir" ]; then
        status="${C_DIM}linked now${C_RESET}"
      elif path_exists "$candidate/inlay.toml"; then
        status="${C_GREEN}has inlay.toml${C_RESET}"
      else
        status="${C_YELLOW}no inlay.toml${C_RESET}"
      fi
      printf '      %s%2d%s  %-32s %s\n' "$C_BOLD" "$n" "$C_RESET" "$(pretty_path "$candidate")" "$status"
    done <<LIST
$found
LIST
  fi

  while true; do
    if [ "$first" = true ] && [ -n "$default" ]; then
      if [ "$count" -gt 1 ]; then
        ask_path "Folder" "a number or a path · Tab completes · Enter = $default_number"
      else
        ask_path "Folder" "Tab completes · Enter = $(pretty_path "$default")"
      fi
      if [ -z "$ANSWER" ]; then ANSWER="$default"; fi
    else
      ask_path "Folder" "Tab completes · Enter keeps your config"
      if [ -z "$ANSWER" ]; then return 1; fi
    fi
    first=false
    answer="$ANSWER"
    case "$answer" in
      *[!0-9]*) ;;
      *)
        if [ "$answer" -ge 1 ] && [ "$answer" -le "$count" ]; then
          answer="$(printf '%s' "$found" | sed -n "${answer}p")"
        fi
        ;;
    esac
    target="$(absolute_path "$answer" "$START_DIR")"
    # Without the trailing slashes: the link is to the folder. Tab leaves one after the name of a folder
    while [ "$target" != / ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done
    status=0
    check_link_target "$dir" "$target" "$current" true || status=$?
    case "$status" in
      0) CHOSEN_FOLDER="$target"; return 0 ;;
      2) return 2 ;;
    esac
    # A folder of the list with the name that was typed is most likely what was meant
    candidate="$(printf '%s' "$found" | grep -m 1 "/$(basename "$target")\$" || true)"
    if [ -n "$candidate" ] && [ "$candidate" != "$target" ]; then
      hint "Did you mean $(pretty_path "$candidate")?"
    fi
  done
}

# link_config_folder <config folder> <link: a folder, or empty> <prompt: true|false>
# Makes the config folder a symbolic link to a folder of the user: the one of --config-link, or the one that the
# user picks after answering yes. It is asked on every run. See "Your own config folder".
# A real config folder is never deleted (it is renamed), and nothing is written to the folder of the user
# without asking
link_config_folder() {
  local dir="$1" target="$2" prompt="$3" current="" legacy="" suggestion="" question backup status=0
  if [ -L "$dir" ]; then
    current="$(readlink "$dir")"
  elif [ -L "$dir/inlay.toml" ]; then
    legacy="$(readlink "$dir/inlay.toml")"
  fi

  if [ -z "$target" ]; then
    if [ "$prompt" != true ]; then
      return 0
    fi
    if ! is_interactive; then
      note "No terminal to ask on: the config stays as it is. (To use a config folder of your own:"
      note "--config-link <folder>)"
      return 0
    fi
    echo
    info "Your own config folder"
    hint "Your config can live in a folder of your own (a dotfiles repo, for example):"
    hint "$(pretty_path "$dir") becomes a symbolic link to it, and Inlay uses the inlay.toml in it."
    question="Use a config folder of your own?"
    if [ -n "$current" ]; then
      hint "Right now it is linked to $(pretty_path "$current")"
      question="Link it to another folder?"
    elif [ -n "$legacy" ]; then
      hint "Right now only the file is linked, the way a previous version did it:"
      hint "$(pretty_path "$dir/inlay.toml") -> $(pretty_path "$legacy")"
      # The folder that holds the linked file is the obvious one to link, if the file has the name Inlay looks for
      if [ "$(basename "$legacy")" = inlay.toml ]; then
        suggestion="$(dirname "$(absolute_path "$legacy" "$dir")")"
      fi
    fi
    if ! ask_yes_no "$question"; then
      if [ -n "$current" ]; then
        ok "Keeping the link to $(pretty_path "$current")"
      else
        ok "Keeping your config as it is: $(pretty_path "$CONFIG_PATH")"
      fi
      return 0
    fi
    choose_config_folder "$dir" "$suggestion" "$current" || status=$?
    case "$status" in
      1) nothing_was_linked; return 0 ;;
      2) return 0 ;;
    esac
    target="$CHOSEN_FOLDER"
  else
    target="$(absolute_path "$target" "$START_DIR")"
    # Without the trailing slashes: the link is to the folder
    while [ "$target" != / ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done
    check_link_target "$dir" "$target" "$current" "$([ "$prompt" = true ] && is_interactive && echo true || echo false)" ||
      status=$?
    case "$status" in
      1) nothing_was_linked; return 0 ;;
      2) return 0 ;;
    esac
  fi

  if [ -n "$current" ]; then
    rm "$dir"
    note "The previous link, to $(pretty_path "$current"), was removed. That folder was not touched."
  elif [ -d "$dir" ]; then
    # The copy that this run has just made, alone in a folder that this run has just made: nothing to keep
    if [ "$CONFIG_CREATED" = true ] && rm -f "$dir/inlay.toml" && rmdir "$dir" 2>/dev/null; then
      :
    else
      backup="$(backup_path "$dir")"
      mv "$dir" "$backup"
      warn "Your previous $(pretty_path "$dir") was not deleted: it is now $(pretty_path "$backup")"
    fi
  fi
  ln -s "$target" "$dir"
  CONFIG_PATH="$dir/inlay.toml"
  ok "Linked $(pretty_path "$dir") ${C_MAGENTA}->${C_RESET} $(pretty_path "$target")"
  hint "Inlay reads and writes $(pretty_path "$target")/inlay.toml"
}

# Says what the parser of the app that was just installed thinks of the config. Never fails the installation
check_config() {
  local binary="$INSTALL_TARGET/Contents/MacOS/$APP_NAME" output status=0
  [ -n "$CONFIG_PATH" ] && [ -x "$binary" ] || return 0
  # A link that leads nowhere, or a linked folder without inlay.toml: there is nothing to check, and it was said
  [ -e "$CONFIG_PATH" ] || return 0
  output="$("$binary" --check-config "$CONFIG_PATH" 2>&1)" || status=$?
  echo
  info "Checking the config"
  case "$output" in
    *"has no errors or warnings") ok "No errors or warnings in $(pretty_path "$CONFIG_PATH")" ;;
    *) printf '%s\n' "$output" | sed 's/^/    /' ;;
  esac
  if [ "$status" -ne 0 ]; then
    warn "the config has errors. Inlay starts anyway and shows them in a window. Fix them and run"
    warn "'$CLI_NAME reload-config' (or just save the file, with 'auto-reload-config = true')."
  fi
}

# What to look at in a config that was written for AeroSpace. Only tells: the copy is never edited
review_imported_config() {
  local file="$1"
  note "Review it. Inlay reads it as it is ('accordion' is accepted with a warning and treated as 'tiles'):"
  note "'$CLI_NAME reload-config' and the menu bar item list the warnings and the errors."
  if grep -Eq '^[[:space:]]*start-at-login[[:space:]]*=[[:space:]]*true' "$file"; then
    note "- It has 'start-at-login = true': Inlay will add itself to the login items the first time it runs."
    note "  If AeroSpace also starts at login, both will start. Set it to false until you pick one."
  fi
  if grep -Eq '^[^#]*(aerospace|AEROSPACE_)' "$file"; then
    note "- It mentions 'aerospace' outside of the comments. Commands and scripts that call the 'aerospace'"
    note "  CLI talk to AeroSpace, not to Inlay: they should call '$CLI_NAME'. Scripts can read INLAY_*"
    note "  variables (the AEROSPACE_* ones are still set for them)."
  fi
  note "- The window borders are 4 points thick, outside of the windows: with gaps under 8 the borders of two"
  note "  neighbors overlap, and with gaps of 8 they touch. The built-in config uses 14."
}

explain_accessibility() {
  echo
  info "Accessibility permission"
  note "Inlay moves and resizes windows through the Accessibility API. The first time it opens, macOS asks"
  note "for the permission: turn Inlay on in ${C_BOLD}System Settings > Privacy & Security > Accessibility${C_RESET}"
  note "(it needs an administrator; on a managed Mac the list may be locked by your IT department)."
  note "Until then Inlay does nothing: its menu bar item shows a warning sign."
  note "If Inlay is on in that list but still asks, remove it from the list (-) and open Inlay again."
  if [ "${SIGNED_WITH:-adhoc}" = adhoc ]; then
    note "This build has an ad hoc signature: macOS forgets the permission every time Inlay is rebuilt or"
    note "reinstalled, and it has to be removed from the list (-) and granted again. To keep it across"
    note "rebuilds it must be signed with the local identity, which is what scripts/install.sh does"
    note "unless it gets --adhoc-signing or the identity can't be created (see the warning above)."
  else
    ok "This build is signed with \"$SIGN_IDENTITY_NAME\": the permission survives rebuilds."
  fi
}

# The last thing the script does: open Inlay, or say why not
open_or_explain() {
  local open_app="$1"
  echo
  find_conflicts
  if [ -n "$CONFLICTS" ]; then
    warn "these apps are running and do the same job as Inlay: $CONFLICTS"
    warn "Two window managers at once fight over your windows, so Inlay was NOT opened, and this script"
    warn "doesn't quit other apps for you. Quit them (AeroSpace and AeroMenu from their menu bar icons;"
    warn "borders with 'brew services stop borders' or 'pkill borders'), and then open Inlay with:"
    warn "  open \"$INSTALL_TARGET\""
    info "Installed. Inlay was NOT opened (see the warning above)."
  elif [ "$open_app" = true ]; then
    info "Opening $APP_NAME" "$(pretty_path "$INSTALL_TARGET")"
    if open "$INSTALL_TARGET"; then
      note "Inlay is open: look for its item in the menu bar (it has no Dock icon and no window)."
      note "The first time, macOS asks for the Accessibility permission (see above): until you grant it, the"
      note "item shows a warning sign and no window is moved. Once it is granted, Inlay sends the open"
      note "windows to their workspaces and arranges them. Right-click the item for the menu and the Settings."
      note "The key bindings are in $([ -n "${CONFIG_PATH:-}" ] && pretty_path "$CONFIG_PATH" || echo "your config") (${C_BOLD}$CLI_NAME config --explain${C_RESET} documents every key)."
    else
      warn "could not open it. Open it by hand:  open \"$INSTALL_TARGET\""
    fi
    echo
    success "Done."
  else
    success "Done." "Inlay was not opened (--no-open). Open it with:  open \"$INSTALL_TARGET\""
  fi
}

main() {
  local open_app=true signing=stable import=false config_link="" prompt=true reset_config=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-open) open_app=false ;;
      --stable-signing) signing=stable ;;
      --adhoc-signing) signing=adhoc ;;
      --import-aerospace) import=true ;;
      --no-prompt) prompt=false ;;
      --reset-config) reset_config=true ;;
      --config-link)
        [ $# -ge 2 ] && [ -n "$2" ] || fail "--config-link needs the path of a folder."
        config_link="$2"
        shift
        ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; fail "unknown option: $1" ;;
    esac
    shift
  done

  check_requirements
  choose_install_dir
  build_app "$signing"
  install_app
  link_cli
  ensure_config "$import" "$config_link" "$prompt" "$reset_config"
  check_config
  explain_accessibility
  open_or_explain "$open_app"
}

# Where the script was run from: a relative config folder is relative to it
START_DIR="$PWD"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRIPT_PATH="scripts/install.sh"
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

# Sourcing the script (for tests) defines the functions without running it.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
