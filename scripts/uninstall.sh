#!/usr/bin/env bash
#
# Quits Inlay and removes it. 'inlay uninstall' runs this script (a copy of it: the script deletes the app
# that contains it), and so does ./uninstall.sh in the repo.
#
#   inlay uninstall             remove the app, the 'inlay' CLI link, the login item and your config
#   inlay uninstall --purge     also remove what is left: the preferences and the runtime files of the app,
#                               and the config backups that 'install.sh' made
#   inlay uninstall --yes       don't ask for confirmation (needed when there is no terminal to ask on)
#   INSTALL_DIR=~/Apps inlay uninstall      remove the copy in that directory only (the default is to
#                                           look in /Applications and ~/Applications)
#   INLAY_BIN_DIR=~/bin inlay uninstall     also look for the CLI link in that directory
#
# It works whether Inlay is running or not. A running Inlay is quit first, and on quit it brings the windows
# of the hidden workspaces back to the screen.
#
# Your config is always removed: ~/.config/inlay and ~/.inlay.toml. What is listed before you confirm:
#   - ~/.config/inlay is a real folder: the folder and everything in it are deleted;
#   - ~/.config/inlay is a symbolic link to a folder of yours (a dotfiles repo): only the link is removed.
#     The folder it points to, and its inlay.toml, are never touched;
#   - a symbolic link inside of a real ~/.config/inlay (an inlay.toml linked by a previous version): the link
#     goes with the folder, and the file it points to is never touched.
# The backups that 'install.sh' made outside of that folder (~/.config/inlay.backup-<date>,
# ~/.inlay.toml.backup-<date>) are kept, unless you pass --purge. A backup that is a symbolic link is removed
# the same way: only the link.
#
# Never removed: the Accessibility entry (remove it in System Settings > Privacy & Security > Accessibility, or
# run 'tccutil reset Accessibility com.davidhiguita.inlay') and the signing identity that
# 'install.sh' created (delete "Inlay Local Code Signing" in Keychain Access).
#
# Nothing of AeroSpace, AeroMenu or borders is touched. To go back to them, open AeroSpace and AeroMenu again
# and run 'brew services start borders'.

set -euo pipefail

usage() { sed -n '3,32s/^# \{0,1\}//p' "$SCRIPT_DIR/uninstall.sh"; }

# Prints the installed copies of the app, one per line: the app that 'inlay uninstall' was run from, and the
# ones in the standard places. With INSTALL_DIR only that directory is looked at instead of the standard places
installed_apps() {
  local app
  {
    printf '%s\n' "${INLAY_UNINSTALL_APP:-}"
    if [ -n "${INSTALL_DIR:-}" ]; then
      printf '%s\n' "$INSTALL_DIR/$APP_NAME.app"
    else
      printf '%s\n' "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"
    fi
  } | while IFS= read -r app; do
    # The physical path, so that the same app reached through two paths is listed once
    if [ -n "$app" ] && [ -d "$app" ]; then
      (cd "$app" && pwd -P)
    fi
  done | sort -u
}

# The login item belongs to the app, so only the app can remove it, and only while it still exists
remove_login_item() {
  local app="$1" binary="$1/Contents/MacOS/$APP_NAME" pid i=0
  [ -x "$binary" ] || return 0
  "$binary" --unregister-login-item >/dev/null 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 50 ]; then
      kill "$pid" 2>/dev/null || true
      break
    fi
    sleep 0.1
  done
  if wait "$pid" 2>/dev/null; then
    info "$app is not in the login items any more"
  else
    note "Could not remove the login item of $app. If Inlay is still listed in"
    note "System Settings > General > Login Items, remove it there."
  fi
}

# Prints the links to the CLI of an Inlay.app, one per line
cli_links() {
  local dir link target
  while IFS= read -r dir; do
    link="$dir/$CLI_NAME"
    [ -n "$dir" ] && [ -L "$link" ] || continue
    target="$(readlink "$link")"
    case "$target" in
      */"$APP_NAME.app/$CLI_PATH_IN_APP") printf '%s\n' "$link" ;;
    esac
  done <<LIST | sort -u
${INLAY_BIN_DIR:-}
$(cli_dir_candidates)
LIST
}

# Prints the config paths that exist, one per line
config_paths() {
  local path
  for path in "$(config_home)/inlay" "$HOME/.inlay.toml"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      printf '%s\n' "$path"
    fi
  done
}

# Prints the config backups that 'install.sh' left outside of the config folder, one per line
config_backups() {
  local path
  for path in "$(config_home)/inlay.backup-"* "$HOME/.inlay.toml.backup-"*; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      printf '%s\n' "$path"
    fi
  done
}

# describe_config_path <path>. One line of the list of what is removed: what the path is and, for a symbolic
# link, that what it points to is kept
describe_config_path() {
  local path="$1" what="${2:-your config}"
  if [ -L "$path" ]; then
    note "- $path ($what: a symbolic link. Only the link is removed:"
    note "  what it points to, $(readlink "$path"), is kept)"
  elif [ -d "$path" ]; then
    note "- $path ($what: the folder and everything in it)"
    if [ -L "$path/inlay.toml" ]; then
      note "  Its inlay.toml is a symbolic link: the file it points to, $(readlink "$path/inlay.toml"), is kept"
    fi
  else
    note "- $path ($what)"
  fi
}

# remove_config_path <path>. A symbolic link is removed as a link: what it points to is never touched
remove_config_path() {
  local path="$1"
  if [ -L "$path" ]; then
    rm -f "$path"
    info "Removed the link $path (what it pointed to was not touched)"
  else
    # Without a trailing slash 'rm -rf' never follows a symbolic link, and it removes the links inside of a
    # folder as links
    rm -rf "$path"
    info "Removed $path"
  fi
}

remove_config() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    remove_config_path "$path"
  done <<LIST
$(config_paths)
LIST
}

purge() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    remove_config_path "$path"
  done <<LIST
$(config_backups)
LIST
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "$RUNTIME_TMP_DIR/$BUNDLE_ID"
  info "Removed the preferences and the runtime files of $BUNDLE_ID"
}

main() {
  local do_purge=false assume_yes=false app link path apps links configs backups
  while [ $# -gt 0 ]; do
    case "$1" in
      --purge) do_purge=true ;;
      -y|--yes) assume_yes=true ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; fail "unknown option: $1" ;;
    esac
    shift
  done

  apps="$(installed_apps)"
  links="$(cli_links)"

  info "This removes $APP_NAME:"
  if [ -n "$apps" ]; then
    while IFS= read -r app; do note "- $app (and its login item)"; done <<LIST
$apps
LIST
  else
    note "- $APP_NAME.app is not installed"
  fi
  if [ -n "$links" ]; then
    while IFS= read -r link; do note "- $link"; done <<LIST
$links
LIST
  fi
  configs="$(config_paths)"
  if [ -n "$configs" ]; then
    while IFS= read -r path; do describe_config_path "$path"; done <<LIST
$configs
LIST
  else
    note "- no config was found (~/.config/inlay, ~/.inlay.toml)"
  fi
  backups="$(config_backups)"
  if [ "$do_purge" = true ]; then
    if [ -n "$backups" ]; then
      while IFS= read -r path; do describe_config_path "$path" "a config backup of install.sh"; done <<LIST
$backups
LIST
    fi
    note "- the preferences and the runtime files of $BUNDLE_ID"
  elif [ -n "$backups" ]; then
    note "Kept: the preferences of the app and the config backups of install.sh (--purge removes them too):"
    while IFS= read -r path; do note "  $path"; done <<LIST
$backups
LIST
  else
    note "Kept: the preferences of the app (--purge removes them too)."
  fi

  if [ "$assume_yes" != true ]; then
    is_interactive || fail "there is no terminal to ask for confirmation on. Run it again with --yes."
    if ! ask_yes_no "Remove $APP_NAME?"; then
      info "Nothing was removed."
      exit 1
    fi
  fi

  quit_running_inlay

  if [ -n "$apps" ]; then
    while IFS= read -r app; do
      remove_login_item "$app"
      info "Removing $app"
      rm -rf "$app"
    done <<LIST
$apps
LIST
  fi

  if [ -n "$links" ]; then
    while IFS= read -r link; do
      rm -f "$link"
      info "Removed $link"
    done <<LIST
$links
LIST
  fi

  remove_config
  if [ "$do_purge" = true ]; then
    purge
  fi
  info "Done"
  note "To go back to AeroSpace: open AeroSpace and AeroMenu, and run 'brew services start borders'."
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

# 'inlay uninstall' runs a temporary copy of this script and of lib.sh, and names its directory here
case "$(basename "${INLAY_UNINSTALL_SELF_DIR:-}")" in
  inlay-uninstall.*) trap 'rm -rf "$INLAY_UNINSTALL_SELF_DIR"' EXIT ;;
esac

# Sourcing the script (for tests) defines the functions without running it.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
