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
#   - creates ~/.config/inlay/inlay.toml from the inlay.toml of the repo, only if you have no Inlay config
#     yet (an existing config, file or symbolic link, is never changed, replaced or deleted), and then asks
#     whether you prefer a symbolic link to a config file of your own instead of that copy;
#   - opens Inlay and tells you what to do the first time (the Accessibility permission).
# Running it again updates the installed app: the running copy is quit first.
#
# Options (none of them is needed):
#   --config-link <path>   make the config a symbolic link to <path> instead of asking. Only when you have no
#                          Inlay config yet, and only if <path> exists: otherwise the copy is kept
#   --no-prompt            don't ask anything: keep the copy of inlay.toml. It's what happens on its own
#                          when there is no terminal to ask on
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

usage() { sed -n '3,39s/^# \{0,1\}//p' "$SCRIPT_PATH"; }

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
  info "Requirements: macOS $macos, Swift $swift (${DEVELOPER_DIR:-selected toolchain})"
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
  info "Installing to $INSTALL_TARGET"
  rm -rf "$INSTALL_TARGET"
  ditto "build/$APP_NAME.app" "$INSTALL_TARGET"
  # Tells Finder and Launch Services that the bundle changed
  touch "$INSTALL_TARGET"
  "$LSREGISTER" -f "$INSTALL_TARGET" >/dev/null 2>&1 || true
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
  info "Linked the CLI: $link -> $source"
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

# ensure_config <import aerospace: true|false> <link: a path, or empty> <prompt: true|false>
# Creates the config only when there is none. Never touches an existing one.
# Sets CONFIG_PATH to the config that Inlay will read, or to nothing if it can't tell (two configs)
ensure_config() {
  local import="$1" link="$2" prompt="$3" xdg dotfile source
  xdg="$(config_home)/inlay/inlay.toml"
  dotfile="$HOME/.inlay.toml"
  CONFIG_PATH=""
  if [ -e "$xdg" ] || [ -L "$xdg" ] || [ -e "$dotfile" ] || [ -L "$dotfile" ]; then
    if { [ -e "$xdg" ] || [ -L "$xdg" ]; } && { [ -e "$dotfile" ] || [ -L "$dotfile" ]; }; then
      warn "both $xdg and $dotfile exist: Inlay will report an ambiguous config until you remove one."
    else
      if [ -e "$xdg" ] || [ -L "$xdg" ]; then CONFIG_PATH="$xdg"; else CONFIG_PATH="$dotfile"; fi
      if [ -L "$CONFIG_PATH" ]; then
        info "You already have a config: $CONFIG_PATH -> $(readlink "$CONFIG_PATH")"
      else
        info "You already have a config: $CONFIG_PATH"
      fi
      note "It was left as it is: nothing was copied, replaced or asked."
    fi
    if [ "$import" = true ]; then
      note "--import-aerospace was ignored: you already have an Inlay config."
    fi
    if [ -n "$link" ]; then
      note "--config-link was ignored: you already have an Inlay config. To link another file, remove"
      note "$xdg and run this script again."
    fi
    return 0
  fi

  mkdir -p "$(dirname "$xdg")"
  CONFIG_PATH="$xdg"
  if [ "$import" = true ] && source="$(aerospace_config)"; then
    # cp follows a symlink, so the result is a regular file of your own
    cp "$source" "$xdg"
    info "Created $xdg from $source"
    review_imported_config "$xdg"
  else
    if [ "$import" = true ]; then
      warn "--import-aerospace: no AeroSpace config found (~/.aerospace.toml). Using the default config."
    fi
    cp inlay.toml "$xdg"
    info "Created $xdg (a copy of the inlay.toml of the repo)"
  fi
  if [ "${XDG_CONFIG_HOME:-$HOME/.config}" != "$HOME/.config" ]; then
    note "XDG_CONFIG_HOME is set in this shell. Inlay only finds the config there if the variable is also set"
    note "for the apps that macOS starts (launchctl setenv). Otherwise it reads ~/.config/inlay/inlay.toml."
  fi

  link_config "$xdg" "$link" "$prompt"
}

# link_config <config> <link: a path, or empty> <prompt: true|false>
# Replaces the config that was just created by a symbolic link to a file of the user: the one of --config-link,
# or the one that the user types. A file that doesn't exist is never linked: the copy stays
link_config() {
  local config="$1" target="$2" prompt="$3" answer=""
  if [ -z "$target" ]; then
    if [ "$prompt" != true ]; then
      return 0
    fi
    if ! is_interactive; then
      note "No terminal to ask on: keeping the copy. (To link a config of your own: --config-link <path>)"
      return 0
    fi
    note "If you keep your config somewhere else (a dotfiles repo), $config"
    note "can be a symbolic link to it instead of this copy."
    if ! ask_yes_no "    Replace the copy with a symbolic link to your own config file?"; then
      note "Keeping the copy."
      return 0
    fi
    printf '    Path of your config file: '
    IFS= read -r answer || answer=""
    if [ -z "$answer" ]; then
      warn "no path was given. Keeping the copy of the default config."
      return 0
    fi
    target="$answer"
  fi

  target="$(absolute_path "$target" "$START_DIR")"
  if [ ! -f "$target" ]; then
    warn "$target is not an existing file. Keeping the copy of the default config at $config"
    return 0
  fi
  rm -f "$config"
  ln -s "$target" "$config"
  info "Linked the config: $config -> $target"
}

# Says what the parser of the app that was just installed thinks of the config. Never fails the installation
check_config() {
  local binary="$INSTALL_TARGET/Contents/MacOS/$APP_NAME" output status=0
  [ -n "$CONFIG_PATH" ] && [ -x "$binary" ] || return 0
  output="$("$binary" --check-config "$CONFIG_PATH" 2>&1)" || status=$?
  info "Checking the config"
  printf '%s\n' "$output" | sed 's/^/    /'
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
  info "Accessibility permission"
  note "Inlay moves and resizes windows through the Accessibility API. The first time it opens, macOS asks"
  note "for the permission: turn Inlay on in System Settings > Privacy & Security > Accessibility"
  note "(it needs an administrator; on a managed Mac the list may be locked by your IT department)."
  note "Until then Inlay does nothing: its menu bar item shows a warning sign."
  note "If Inlay is on in that list but still asks, remove it from the list (-) and open Inlay again."
  if [ "${SIGNED_WITH:-adhoc}" = adhoc ]; then
    note "This build has an ad hoc signature: macOS forgets the permission every time Inlay is rebuilt or"
    note "reinstalled, and it has to be removed from the list (-) and granted again. To keep it across"
    note "rebuilds it must be signed with the local identity, which is what scripts/install.sh does"
    note "unless it gets --adhoc-signing or the identity can't be created (see the warning above)."
  else
    note "This build is signed with \"$SIGN_IDENTITY_NAME\": the permission survives rebuilds."
  fi
}

# The last thing the script does: open Inlay, or say why not
open_or_explain() {
  local open_app="$1"
  find_conflicts
  if [ -n "$CONFLICTS" ]; then
    warn "these apps are running and do the same job as Inlay: $CONFLICTS"
    warn "Two window managers at once fight over your windows, so Inlay was NOT opened, and this script"
    warn "doesn't quit other apps for you. Quit them (AeroSpace and AeroMenu from their menu bar icons;"
    warn "borders with 'brew services stop borders' or 'pkill borders'), and then open Inlay with:"
    warn "  open \"$INSTALL_TARGET\""
    info "Installed. Inlay was NOT opened (see the warning above)."
  elif [ "$open_app" = true ]; then
    info "Opening $APP_NAME now ($INSTALL_TARGET)"
    if open "$INSTALL_TARGET"; then
      note "Inlay is open: look for its item in the menu bar (it has no Dock icon and no window)."
      note "The first time, macOS asks for the Accessibility permission (see above): until you grant it, the"
      note "item shows a warning sign and no window is moved. Once it is granted, Inlay sends the open"
      note "windows to their workspaces and arranges them. Right-click the item for the menu and the Settings."
      note "The key bindings are in $([ -n "${CONFIG_PATH:-}" ] && echo "$CONFIG_PATH" || echo "your config") ('$CLI_NAME config --explain' documents every key)."
    else
      warn "could not open it. Open it by hand:  open \"$INSTALL_TARGET\""
    fi
    info "Done."
  else
    info "Done. Inlay was not opened (--no-open). Open it with:  open \"$INSTALL_TARGET\""
  fi
}

main() {
  local open_app=true signing=stable import=false config_link="" prompt=true
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-open) open_app=false ;;
      --stable-signing) signing=stable ;;
      --adhoc-signing) signing=adhoc ;;
      --import-aerospace) import=true ;;
      --no-prompt) prompt=false ;;
      --config-link)
        [ $# -ge 2 ] && [ -n "$2" ] || fail "--config-link needs a path."
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
  ensure_config "$import" "$config_link" "$prompt"
  check_config
  explain_accessibility
  open_or_explain "$open_app"
}

# Where the script was run from: a relative --config-link is relative to it
START_DIR="$PWD"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRIPT_PATH="scripts/install.sh"
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

# Sourcing the script (for tests) defines the functions without running it.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
