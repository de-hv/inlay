#!/usr/bin/env bash
#
# Builds Inlay and installs it. Needs only the Xcode Command Line Tools: no Xcode, no Apple ID.
#
#   scripts/install.sh                      build, install and open Inlay
#   scripts/install.sh --no-open            build and install only
#   scripts/install.sh --adhoc-signing      sign ad hoc instead of with the local identity (see below)
#   scripts/install.sh --import-aerospace   start from your AeroSpace config instead of the default one
#   INSTALL_DIR=~/Applications scripts/install.sh
#   INLAY_BIN_DIR=~/bin scripts/install.sh  where to link the 'inlay' CLI
#
# What it does:
#   - installs Inlay.app into /Applications (or ~/Applications if /Applications isn't writable);
#   - links the 'inlay' CLI into ~/.local/bin, /opt/homebrew/bin or /usr/local/bin;
#   - creates ~/.config/inlay/inlay.toml, only if you have no Inlay config yet. An existing config is never
#     changed or deleted.
# Running it again updates the installed app: the running copy is quit first.
#
# Signing: macOS ties the Accessibility permission to the signature of the app. So the app is signed with a
# self-signed code signing identity ("Inlay Local Code Signing") that is created, once, in your login keychain:
# the permission survives the rebuilds. macOS may ask for your keychain password the first time codesign uses
# the key: choose "Always Allow". If the identity can't be created or used, the app is signed ad hoc, with a
# warning. --adhoc-signing skips the identity: with an ad hoc signature the permission is lost on every rebuild.
# (--stable-signing is still accepted: it's the default now.)
#
# AeroSpace, AeroMenu and borders (JankyBorders) do the same job as Inlay. This script never quits them: if one
# is running it tells you, and leaves Inlay closed until you quit them yourself.

set -euo pipefail

usage() { sed -n '3,27s/^# \{0,1\}//p' "$SCRIPT_PATH"; }

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

# Creates the config only when there is none. Never touches an existing one.
ensure_config() {
  local import="$1" xdg dotfile source
  xdg="$(config_home)/inlay/inlay.toml"
  dotfile="$HOME/.inlay.toml"
  if [ -e "$xdg" ] || [ -L "$xdg" ] || [ -e "$dotfile" ] || [ -L "$dotfile" ]; then
    if { [ -e "$xdg" ] || [ -L "$xdg" ]; } && { [ -e "$dotfile" ] || [ -L "$dotfile" ]; }; then
      warn "both $xdg and $dotfile exist: Inlay will report an ambiguous config until you remove one."
    else
      info "Keeping your config ($([ -e "$xdg" ] || [ -L "$xdg" ] && echo "$xdg" || echo "$dotfile"))"
    fi
    if [ "$import" = true ]; then
      note "--import-aerospace was ignored: you already have an Inlay config."
    fi
    return 0
  fi

  mkdir -p "$(dirname "$xdg")"
  if [ "$import" = true ]; then
    if source="$(aerospace_config)"; then
      # cp follows a symlink, so the result is a regular file of your own
      cp "$source" "$xdg"
      info "Created $xdg from $source"
      review_imported_config "$xdg"
      return 0
    fi
    warn "--import-aerospace: no AeroSpace config found (~/.aerospace.toml). Using the default config."
  fi
  cp docs/config-examples/default-config.toml "$xdg"
  info "Created $xdg from the default config"
  if [ "$import" != true ] && source="$(aerospace_config)"; then
    note "You have an AeroSpace config at $source. To start from it instead, remove"
    note "$xdg and run: scripts/install.sh --import-aerospace"
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

main() {
  local open_app=true signing=stable import=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-open) open_app=false ;;
      --stable-signing) signing=stable ;;
      --adhoc-signing) signing=adhoc ;;
      --import-aerospace) import=true ;;
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
  ensure_config "$import"
  explain_accessibility

  find_conflicts
  if [ -n "$CONFLICTS" ]; then
    warn "these apps are running and do the same job as Inlay: $CONFLICTS"
    warn "Two window managers at once fight over your windows. Quit them before opening Inlay"
    warn "(AeroSpace and AeroMenu from their menu bar icons; borders with 'brew services stop borders'"
    warn "or 'pkill borders'), then open it with:  open \"$INSTALL_TARGET\""
    info "Installed. Inlay was NOT opened."
  elif [ "$open_app" = true ]; then
    info "Opening $APP_NAME"
    open "$INSTALL_TARGET"
    info "Done."
  else
    info "Done. Open it with:  open \"$INSTALL_TARGET\""
  fi
}

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRIPT_PATH="scripts/install.sh"
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

# Sourcing the script (for tests) defines the functions without running it.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
