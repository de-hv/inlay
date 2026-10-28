#!/usr/bin/env bash
#
# Quits Inlay and removes it. 'inlay uninstall' runs this script (a copy of it: the script deletes the app
# that contains it), and so does ./uninstall.sh in the repo.
#
#   inlay uninstall             pick what to remove in a list, see what is removed and what is kept, confirm
#   inlay uninstall --purge     everything starts checked in the list (but the Accessibility entry)
#   inlay uninstall --yes       don't ask: remove the app, the 'inlay' CLI link, the login item and your config
#                               (and with --purge the preferences, the runtime files and the config backups too).
#                               Needed when there is no terminal to ask on
#   INSTALL_DIR=~/Apps inlay uninstall      remove the copy in that directory only (the default is to
#                                           look in /Applications and ~/Applications)
#   INLAY_BIN_DIR=~/bin inlay uninstall     also look for the CLI link in that directory
#
# The list: the app and its login item, the CLI link, your config, the config backups, the preferences and the
# runtime files of the app, and its Accessibility entry. The app and the CLI link start checked; your config
# doesn't: check it to remove it. Space checks and unchecks, Enter is done. Then the script lists what is removed,
# what is kept and what it never touches, and asks for confirmation. Without a terminal that shows colors the list
# is one question per line.
#
# It works whether Inlay is running or not. A running Inlay is quit first, and on quit it brings the windows
# of the hidden workspaces back to the screen.
#
# Your config is ~/.config/inlay and ~/.inlay.toml. When it is removed:
#   - a real file or folder is saved first in ~/inlay-config-<date>.tar.gz, and then deleted;
#   - ~/.config/inlay is a symbolic link to a folder of yours (a dotfiles repo): only the link is removed.
#     The folder it points to, and its inlay.toml, are never touched;
#   - a symbolic link inside of a real ~/.config/inlay (an inlay.toml linked by a previous version): the link
#     goes with the folder, and the file it points to is never touched.
# The config backups are the ones that 'install.sh' made outside of that folder (~/.config/inlay.backup-<date>,
# ~/.inlay.toml.backup-<date>). A backup that is a symbolic link is removed the same way: only the link.
#
# The Accessibility entry is only removed when it is checked: 'tccutil reset Accessibility com.dehv.inlay'.
# Never removed: the signing identity that 'install.sh' created (delete "Inlay Local Code Signing" in Keychain
# Access).
#
# Nothing of AeroSpace, AeroMenu or borders is touched. To go back to them, open AeroSpace and AeroMenu again
# and run 'brew services start borders'.

set -euo pipefail

# The comment at the top of this file, without the '#'
usage() { awk 'NR < 3 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SCRIPT_DIR/uninstall.sh"; }

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
  if ! wait "$pid" 2>/dev/null; then
    warn "could not remove the login item of $(pretty_path "$app"). If Inlay is still listed in"
    warn "System Settings > General > Login Items, remove it there."
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

# The app has preferences or runtime files
has_preferences() {
  defaults read "$BUNDLE_ID" >/dev/null 2>&1 || [ -e "$RUNTIME_TMP_DIR/$BUNDLE_ID" ]
}

# human_size <path>: '48 MB'
human_size() {
  local kb
  kb="$(du -sk "$1" 2>/dev/null | cut -f 1)"
  case "$kb" in
    ''|*[!0-9]*) ;;
    *) if [ "$kb" -ge 1024 ]; then printf '%d MB\n' $((kb / 1024)); else printf '%d KB\n' "$kb"; fi ;;
  esac
}

# describe_config <path>: what a config path is, in a few words
describe_config() {
  local count
  if [ -L "$1" ]; then
    printf 'a link to %s\n' "$(pretty_path "$(readlink "$1")")"
  elif [ -d "$1" ]; then
    count="$(find "$1" \( -type f -o -type l \) | wc -l | tr -d ' ')"
    if [ "$count" = 1 ]; then printf 'a folder, 1 file\n'; else printf 'a folder, %s files\n' "$count"; fi
  else
    printf 'a file\n'
  fi
}

# Prints "<first one>", or "<first one> and N more", of a list of paths
first_of() {
  local first count
  first="$(printf '%s\n' "$1" | head -n 1)"
  count="$(printf '%s\n' "$1" | grep -c . || true)"
  if [ "$count" -gt 1 ]; then
    printf '%s and %d more\n' "$(pretty_path "$first")" $((count - 1))
  else
    printf '%s\n' "$(pretty_path "$first")"
  fi
}

# preview_heading <removed|kept|untouched> <title>
preview_heading() {
  local color="$C_DIM"
  case "$1" in
    removed) color="$C_RED" ;;
    kept) color="$C_GREEN" ;;
  esac
  echo
  if [ -n "$C_RESET" ]; then printf '  %s%s%s\n' "$color" "$2" "$C_RESET"; else printf '    %s:\n' "$2"; fi
}

# preview_row <removed|kept|untouched> <what> <detail>. A line of the list of what happens
preview_row() {
  local mark plain
  case "$1" in
    removed) mark="${C_RED}✗$C_RESET" plain="-" ;;
    kept) mark="${C_GREEN}✓$C_RESET" plain="+" ;;
    *) mark="${C_DIM}·$C_RESET" plain="." ;;
  esac
  if [ -n "$C_RESET" ]; then
    printf '   %s %-38s %s%s%s\n' "$mark" "$2" "$C_DIM" "$3" "$C_RESET"
  else
    printf '    %s %-38s %s\n' "$plain" "$2" "$3"
  fi
}

# rows_for_paths <removed|kept> <paths> <what they are>. One row per path; for a symbolic link that is removed,
# what it points to is kept
rows_for_paths() {
  local group="$1" path detail
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ "$group" = kept ]; then
      detail="$3"
    elif [ -L "$path" ]; then
      detail="$3: only the link"
    elif [ "$3" = "your config" ]; then
      detail="$3, $(describe_config "$path"): a copy is saved first"
    else
      detail="$3, $(describe_config "$path")"
    fi
    preview_row "$group" "$(pretty_path "$path")" "$detail"
  done <<LIST
$2
LIST
}

# What a removed link points to: kept. One row per link
rows_for_link_targets() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -L "$path" ]; then
      preview_row kept "$(pretty_path "$(readlink "$path")")" "what $(pretty_path "$path") points to"
    elif [ -d "$path" ] && [ -L "$path/inlay.toml" ]; then
      preview_row kept "$(pretty_path "$(readlink "$path/inlay.toml")")" "what $(pretty_path "$path")/inlay.toml points to"
    fi
  done <<LIST
$1
LIST
}

# remove_config_path <path>. A symbolic link is removed as a link: what it points to is never touched
remove_config_path() {
  local path="$1"
  if [ -L "$path" ]; then
    rm -f "$path"
    ok "Removed the link $(pretty_path "$path") ${C_DIM}· what it pointed to was not touched${C_RESET}"
  else
    # Without a trailing slash 'rm -rf' never follows a symbolic link, and it removes the links inside of a
    # folder as links
    rm -rf "$path"
    ok "Removed $(pretty_path "$path")"
  fi
}

# save_config_copy <config paths>. Saves the real files and folders of the config (not what the links point to)
# in ~/inlay-config-<date>.tar.gz before they are deleted
save_config_copy() {
  local path archive args=()
  while IFS= read -r path; do
    [ -n "$path" ] && [ ! -L "$path" ] || continue
    args+=(-C "$(dirname "$path")" "$(basename "$path")")
  done <<LIST
$1
LIST
  [ "${#args[@]}" -gt 0 ] || return 0
  archive="$HOME/inlay-config-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$archive" "${args[@]}" || fail "could not save a copy of your config in $archive. Nothing was removed."
  ok "Saved a copy of your config: $(pretty_path "$archive")"
}

main() {
  local do_purge=false assume_yes=false apps links configs backups version app link path
  local keys options purge_state count i kept
  local remove_app=false remove_cli=false remove_config=false remove_backups=false remove_prefs=false remove_tcc=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --purge) do_purge=true ;;
      -y|--yes) assume_yes=true ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; fail "unknown option: $1" ;;
    esac
    shift
  done
  if [ "$assume_yes" != true ]; then
    is_interactive || fail "there is no terminal to ask for confirmation on. Run it again with --yes."
  fi

  apps="$(installed_apps)"
  links="$(cli_links)"
  configs="$(config_paths)"
  backups="$(config_backups)"
  version=""
  if [ -n "$apps" ]; then version="$(app_version "$(printf '%s\n' "$apps" | head -n 1)")"; fi

  echo
  if [ -n "$C_RESET" ]; then
    printf '  %sUninstall %s%s%s' "$C_BOLD" "$APP_NAME" "${version:+ $version}" "$C_RESET"
  else
    printf '==> Uninstall %s%s' "$APP_NAME" "${version:+ $version}"
  fi
  if [ -z "$apps" ]; then
    printf '  %s(%s.app is not installed)%s\n' "$C_DIM" "$APP_NAME" "$C_RESET"
  elif inlay_is_running; then
    printf '  %s(running: it is quit first)%s\n' "$C_DIM" "$C_RESET"
  else
    echo
  fi

  # What can be removed, the things that are there. --yes takes what is checked at first; --purge checks it all
  purge_state=off
  if [ "$do_purge" = true ]; then purge_state=on; fi
  keys=()
  options=()
  if [ -n "$apps" ]; then
    keys+=(app)
    options+=("on${TAB}App and login item${TAB}$(first_of "$apps") · $(human_size "$(printf '%s\n' "$apps" | head -n 1)")")
  fi
  if [ -n "$links" ]; then
    keys+=(cli)
    options+=("on${TAB}CLI link${TAB}$(first_of "$links")")
  fi
  if [ -n "$configs" ]; then
    keys+=(config)
    if [ "$assume_yes" = true ]; then
      options+=("on${TAB}Your config${TAB}")
    else
      options+=("$purge_state${TAB}Your config${TAB}$(first_of "$configs") · $(describe_config "$(printf '%s\n' "$configs" | head -n 1)")")
    fi
  fi
  if [ -n "$backups" ]; then
    count="$(printf '%s\n' "$backups" | grep -c . || true)"
    keys+=(backups)
    options+=("$purge_state${TAB}Config backups ($count)${TAB}$(pretty_path "$(config_home)")/inlay.backup-*")
  fi
  if has_preferences; then
    keys+=(prefs)
    options+=("$purge_state${TAB}Preferences and runtime files${TAB}$BUNDLE_ID")
  fi
  keys+=(tcc)
  options+=("off${TAB}Accessibility entry${TAB}tccutil reset Accessibility")

  if [ "$assume_yes" = true ]; then
    CHOSEN=" "
    i=0
    while [ "$i" -lt "${#options[@]}" ]; do
      case "${options[$i]}" in on"$TAB"*) CHOSEN="$CHOSEN$((i + 1)) " ;; esac
      i=$((i + 1))
    done
  else
    echo
    choose_many "What should be removed?" "↑↓ · Space checks · a all · Enter" "${options[@]}"
  fi
  i=0
  while [ "$i" -lt "${#keys[@]}" ]; do
    case "$CHOSEN" in
      *" $((i + 1)) "*)
        case "${keys[$i]}" in
          app) remove_app=true ;;
          cli) remove_cli=true ;;
          config) remove_config=true ;;
          backups) remove_backups=true ;;
          prefs) remove_prefs=true ;;
          tcc) remove_tcc=true ;;
        esac
        ;;
    esac
    i=$((i + 1))
  done
  if [ "$CHOSEN" = " " ]; then
    echo
    info "Nothing was removed."
    exit 1
  fi

  # What happens: removed, kept, never touched
  preview_heading removed "Removed"
  if [ "$remove_app" = true ]; then
    while IFS= read -r app; do
      preview_row removed "$(pretty_path "$app")" "$(human_size "$app") · and its login item"
    done <<LIST
$apps
LIST
  fi
  if [ "$remove_cli" = true ]; then rows_for_paths removed "$links" "the CLI"; fi
  if [ "$remove_config" = true ]; then rows_for_paths removed "$configs" "your config"; fi
  if [ "$remove_backups" = true ]; then rows_for_paths removed "$backups" "a config backup"; fi
  if [ "$remove_prefs" = true ]; then preview_row removed "Preferences and runtime files" "$BUNDLE_ID"; fi
  if [ "$remove_tcc" = true ]; then preview_row removed "Accessibility entry" "tccutil reset Accessibility"; fi

  kept="$(
    if [ "$remove_config" = true ]; then rows_for_link_targets "$configs"; fi
    if [ "$remove_backups" = true ]; then rows_for_link_targets "$backups"; fi
    if [ "$remove_app" != true ] && [ -n "$apps" ]; then rows_for_paths kept "$apps" "the app"; fi
    if [ "$remove_cli" != true ]; then rows_for_paths kept "$links" "the CLI link"; fi
    if [ "$remove_config" != true ]; then rows_for_paths kept "$configs" "your config"; fi
    if [ "$remove_backups" != true ]; then rows_for_paths kept "$backups" "a config backup"; fi
    if [ "$remove_prefs" != true ] && has_preferences; then
      preview_row kept "Preferences and runtime files" "$BUNDLE_ID"
    fi
  )"
  if [ -n "$kept" ]; then
    preview_heading kept "Kept"
    printf '%s\n' "$kept"
  fi

  preview_heading untouched "Not touched · do it by hand if you want"
  if [ "$remove_tcc" != true ]; then
    preview_row untouched "Accessibility entry" "tccutil reset Accessibility $BUNDLE_ID"
  fi
  preview_row untouched "Signing identity" "Keychain Access > \"$SIGN_IDENTITY_NAME\""

  if [ "$assume_yes" != true ]; then
    echo
    if ! ask_yes_no "Remove what is listed under Removed?"; then
      info "Nothing was removed."
      exit 1
    fi
  fi
  echo

  if [ "$remove_config" = true ]; then save_config_copy "$configs"; fi
  if [ "$remove_app" = true ] || [ "$remove_prefs" = true ]; then quit_running_inlay; fi

  if [ "$remove_app" = true ]; then
    while IFS= read -r app; do
      remove_login_item "$app"
      rm -rf "$app"
      ok "Removed $(pretty_path "$app") ${C_DIM}· and its login item${C_RESET}"
    done <<LIST
$apps
LIST
  fi

  if [ "$remove_cli" = true ]; then
    while IFS= read -r link; do
      rm -f "$link"
      ok "Removed $(pretty_path "$link")"
    done <<LIST
$links
LIST
  fi

  for path in config backups; do
    if [ "$path" = config ] && [ "$remove_config" = true ]; then
      printf '%s\n' "$configs"
    elif [ "$path" = backups ] && [ "$remove_backups" = true ]; then
      printf '%s\n' "$backups"
    fi
  done | while IFS= read -r path; do
    [ -n "$path" ] || continue
    remove_config_path "$path"
  done

  if [ "$remove_prefs" = true ]; then
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$RUNTIME_TMP_DIR/$BUNDLE_ID"
    ok "Removed the preferences and the runtime files of $BUNDLE_ID"
  fi

  if [ "$remove_tcc" = true ]; then
    if tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1; then
      ok "Removed the Accessibility entry"
    else
      warn "could not remove the Accessibility entry: remove Inlay in System Settings > Privacy & Security >"
      warn "Accessibility (-)."
    fi
  fi

  echo
  if [ "$remove_app" = true ]; then
    success "$APP_NAME was removed."
    hint "To install it again: ./install.sh in the Inlay repo."
  else
    success "Done."
  fi
  hint "To go back to AeroSpace: open AeroSpace and AeroMenu, and run 'brew services start borders'."
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
