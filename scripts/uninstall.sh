#!/usr/bin/env bash
#
# Quits Inlay and removes it. 'inlay uninstall' runs this script (a copy of it: the script deletes the app
# that contains it), and so does ./uninstall.sh in the repo.
#
#   inlay uninstall             remove the app, the 'inlay' CLI link and the login item
#   inlay uninstall --purge     also remove your config and the app's preferences
#   inlay uninstall --yes       don't ask for confirmation (needed when there is no terminal to ask on)
#   INSTALL_DIR=~/Apps inlay uninstall      remove the copy in that directory only (the default is to
#                                           look in /Applications and ~/Applications)
#   INLAY_BIN_DIR=~/bin inlay uninstall     also look for the CLI link in that directory
#
# It works whether Inlay is running or not. A running Inlay is quit first, and on quit it brings the windows
# of the hidden workspaces back to the screen.
# Without --purge your config (~/.config/inlay, ~/.inlay.toml) is kept. With --purge it is removed; if it is
# a symbolic link to a file of yours, only the link is removed, never the file it points to.
# Never removed: the Accessibility entry (remove it in System Settings > Privacy & Security > Accessibility, or
# run 'tccutil reset Accessibility com.davidhiguita.inlay') and the signing identity that
# 'install.sh' created (delete "Inlay Local Code Signing" in Keychain Access).
#
# Nothing of AeroSpace, AeroMenu or borders is touched. To go back to them, open AeroSpace and AeroMenu again
# and run 'brew services start borders'.

set -euo pipefail

usage() { sed -n '3,23s/^# \{0,1\}//p' "$SCRIPT_DIR/uninstall.sh"; }

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

# Prints, for a config path, the symbolic links that 'rm' removes without touching what they point to:
# "<link> -> <target>" per line. The path itself, or the config file inside the config directory
config_links() {
  local path="$1" candidate
  for candidate in "$path" "$path/inlay.toml"; do
    if [ -L "$candidate" ]; then
      printf '%s -> %s\n' "$candidate" "$(readlink "$candidate")"
    fi
  done
}

purge() {
  local path link
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    while IFS= read -r link; do
      [ -n "$link" ] || continue
      note "Symbolic link: only the link is removed, the file it points to is kept ($link)"
    done <<LINKS
$(config_links "$path")
LINKS
    # Without a trailing slash 'rm -rf' never follows a symbolic link
    rm -rf "$path"
    info "Removed $path"
  done <<LIST
$(config_paths)
LIST
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "$RUNTIME_TMP_DIR/$BUNDLE_ID"
  info "Removed the preferences of $BUNDLE_ID"
}

main() {
  local do_purge=false assume_yes=false app link apps links
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
  if [ "$do_purge" = true ]; then
    while IFS= read -r link; do
      [ -n "$link" ] || continue
      note "- $link (your config)"
    done <<LIST
$(config_paths)
LIST
    note "- the preferences of $BUNDLE_ID"
  else
    note "Your config is kept (use --purge to remove it too)."
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
