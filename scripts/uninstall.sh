#!/usr/bin/env bash
#
# Quits Inlay and removes it.
#
#   scripts/uninstall.sh            remove the app, the 'inlay' CLI link and the login item
#   scripts/uninstall.sh --purge    also remove your config and the app's preferences
#   INSTALL_DIR=~/Apps scripts/uninstall.sh      remove the copy in that directory only (the default is to
#                                                look in /Applications and ~/Applications)
#   INLAY_BIN_DIR=~/bin scripts/uninstall.sh
#
# Without --purge your config (~/.config/inlay, ~/.inlay.toml) is kept.
# Never removed: the Accessibility entry (remove it in System Settings > Privacy & Security > Accessibility, or
# run 'tccutil reset Accessibility com.davidhiguita.inlay') and the signing identity that
# 'install.sh' created (delete "Inlay Local Code Signing" in Keychain Access).
#
# Nothing of AeroSpace, AeroMenu or borders is touched. To go back to them, open AeroSpace and AeroMenu again
# and run 'brew services start borders'.

set -euo pipefail

usage() { sed -n '3,17s/^# \{0,1\}//p' "$SCRIPT_PATH"; }

# Prints the installed copies of the app, one per line.
# With INSTALL_DIR only that directory is looked at: the copies in the standard places are left alone
installed_apps() {
  local dir
  if [ -n "${INSTALL_DIR:-}" ]; then
    if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
      printf '%s\n' "$INSTALL_DIR/$APP_NAME.app"
    fi
    return 0
  fi
  for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/$APP_NAME.app" ]; then
      printf '%s\n' "$dir/$APP_NAME.app"
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

remove_cli_links() {
  local dir link target
  while IFS= read -r dir; do
    link="$dir/$CLI_NAME"
    [ -n "$dir" ] && [ -L "$link" ] || continue
    target="$(readlink "$link")"
    case "$target" in
      */"$APP_NAME.app/$CLI_PATH_IN_APP")
        rm -f "$link"
        info "Removed $link"
        ;;
    esac
  done <<LIST
${INLAY_BIN_DIR:-}
$(cli_dir_candidates)
LIST
}

purge() {
  local path
  for path in "$(config_home)/inlay" "$HOME/.inlay.toml"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      rm -rf "$path"
      info "Removed $path"
    fi
  done
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "/tmp/$BUNDLE_ID"
  info "Removed the preferences of $BUNDLE_ID"
}

main() {
  local do_purge=false app found=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --purge) do_purge=true ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; fail "unknown option: $1" ;;
    esac
    shift
  done

  quit_running_inlay

  while IFS= read -r app; do
    [ -n "$app" ] || continue
    found=true
    remove_login_item "$app"
    info "Removing $app"
    rm -rf "$app"
  done <<LIST
$(installed_apps)
LIST
  [ "$found" = true ] || info "$APP_NAME.app is not installed"

  remove_cli_links

  if [ "$do_purge" = true ]; then
    purge
  else
    note "Your config was kept. Use --purge to remove it too."
  fi
  info "Done"
  note "To go back to AeroSpace: open AeroSpace and AeroMenu, and run 'brew services start borders'."
}

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRIPT_PATH="scripts/uninstall.sh"
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

# Sourcing the script (for tests) defines the functions without running it.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
