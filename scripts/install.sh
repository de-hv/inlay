#!/usr/bin/env bash
#
# Builds Inlay, installs it and opens it. Needs only the Xcode Command Line Tools: no Xcode, no Apple ID.
# No option is needed:
#
#   ./install.sh
#
# First it checks the requirements, all of them, and shows how to fix what is missing. Then it says what it is
# going to do (where it installs, what happens to your config) and asks to go on. Then, in 5 steps:
#   1. builds Inlay.app and signs it with a local identity, so that macOS keeps the Accessibility permission
#      across rebuilds (see "Signing" below). On a terminal one line says how far the build is: its whole
#      output goes to ~/Library/Logs/Inlay/install-<date>.log (--verbose shows it as it comes);
#   2. installs it into /Applications (or ~/Applications if /Applications isn't writable);
#   3. links the 'inlay' CLI into ~/.local/bin, /opt/homebrew/bin or /usr/local/bin;
#   4. creates ~/.config/inlay/inlay.toml from the inlay.toml of the repo if you have no Inlay config yet
#      (what happens to a config that you already have: see "Your config" below), and asks, every time, where
#      your config should live: where it is, or in a folder of your own through a symbolic link (see "Your own
#      config folder" below). Enter keeps what you have;
#   5. opens Inlay. A summary says where everything is and what to do the first time (the Accessibility
#      permission).
# Running it again updates the installed app: the running copy is quit first.
#
# Your config: a config that you already have is yours, and it is never edited, replaced or deleted without
# asking. With one exception: a config that is identical, byte for byte, to a default config that a previous
# version of Inlay installed (scripts/default-config-hashes.txt) was never edited by anybody, so it is replaced
# by the current inlay.toml, and the old one is kept next to it as inlay.toml.backup-<date>. Any other config is
# kept as it is, and the script lists the settings of the inlay.toml of the repo that it doesn't have. On a
# terminal it then offers to show the whole diff, or to switch to the inlay.toml of the repo (yours is kept as
# inlay.toml.backup-<date>). --reset-config is how you switch without being asked.
#
# Your own config folder: the question lists the folders of a dotfiles repo that it finds (~/.dotfiles/inlay,
# ~/dotfiles/inlay…): pick one with the arrows, or "Another folder..." to type a path (Tab completes it).
# ~/.config/inlay becomes a symbolic link to that folder. Inlay reads and writes the inlay.toml in it; nothing
# else of the folder is touched.
#   - A folder of the list without inlay.toml gets a copy of the inlay.toml of the repo.
#   - A typed folder that doesn't exist, or can't be linked: the script says why and asks again. Enter with
#     nothing keeps your config as it is. A typed folder without inlay.toml: the script asks whether to copy
#     the inlay.toml of the repo into it. If you say no, it asks for another folder.
#   - You already had a real ~/.config/inlay: it is not deleted. It is renamed to ~/.config/inlay.backup-<date>.
#   - ~/.config/inlay already is a link: the first option keeps it. Linking another folder only replaces the
#     link: the folder it pointed to is not touched.
#   - A previous version linked the file instead (~/.config/inlay/inlay.toml -> your file). It still works and
#     it is left alone; the folder that holds that file is in the list, to link it instead.
# A linked folder is yours: its inlay.toml is never replaced, not even when it is identical to an old default
# config.
#
# Options (none of them is needed):
#   --config-link <folder> link ~/.config/inlay to <folder> without asking, with the same rules as above. A
#                          folder without inlay.toml is only filled in if there is a terminal to ask on
#   -y, --yes              don't ask before starting. The questions about the config are still asked
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
#   --verbose              show the output of the build as it comes
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

# The comment at the top of this file, without the '#'
usage() { awk 'NR < 3 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SCRIPT_PATH"; }

# 'Inlay 0.1.0 installer' and the commit it builds
print_header() {
  local hash
  hash="$(git rev-parse --short HEAD 2>/dev/null || echo SNAPSHOT)"
  if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then hash="$hash-dirty"; fi
  if [ -n "$C_RESET" ]; then
    echo
    printf '  %s▟▙%s  %s%s %s%s  %sinstaller%s\n' "$C_BOLD$C_CYAN" "$C_RESET" "$C_BOLD" "$APP_NAME" "$REPO_VERSION" \
      "$C_RESET" "$C_DIM" "$C_RESET"
    printf '  %s▜▛%s  %sa tiling window manager for macOS · %s%s\n' "$C_BOLD$C_CYAN" "$C_RESET" "$C_DIM" "$hash" "$C_RESET"
    echo
  else
    printf '==> %s %s installer (%s)\n' "$APP_NAME" "$REPO_VERSION" "$hash"
  fi
}

# Checks every requirement, not only up to the first one that is missing, and says how to fix what is missing.
# Sets SWIFT_VERSION
check_requirements() {
  local macos problems=0 fix="" notes=""
  SWIFT_VERSION=""
  info "Requirements"

  macos="$(sw_vers -productVersion)"
  if version_at_least "$macos" 14 0; then
    requirement_row ok "macOS $macos" "${C_DIM}needs 14 or later${C_RESET}"
  else
    requirement_row bad "macOS $macos" "${C_RED}Inlay needs macOS 14 or later${C_RESET}"
    problems=$((problems + 1))
    notes="${notes}Update macOS in System Settings > General > Software Update, if this Mac supports macOS 14."$'\n'
  fi

  if [ "${INLAY_USE_SELECTED_TOOLCHAIN:-0}" = 1 ]; then
    if command -v swift >/dev/null 2>&1; then
      requirement_row ok "Selected toolchain" "${C_DIM}INLAY_USE_SELECTED_TOOLCHAIN=1${C_RESET}"
    else
      requirement_row bad "Selected toolchain" "${C_RED}swift was not found${C_RESET}"
      problems=$((problems + 1))
    fi
  elif [ -x "$CLT_DIR/usr/bin/swift" ]; then
    export DEVELOPER_DIR="$CLT_DIR"
    requirement_row ok "Command Line Tools" "${C_DIM}$CLT_DIR${C_RESET}"
  else
    requirement_row bad "Command Line Tools" "${C_RED}not installed${C_RESET}${C_DIM} · Xcode is not needed${C_RESET}"
    problems=$((problems + 1))
    fix="xcode-select --install"
  fi

  if [ -z "$fix" ] && command -v swift >/dev/null 2>&1; then SWIFT_VERSION="$(swift_version)"; fi
  if [ -n "$fix" ]; then
    requirement_row bad "Swift 6.2" "${C_DIM}comes with the Command Line Tools${C_RESET}"
  elif [ -z "$SWIFT_VERSION" ]; then
    requirement_row bad "Swift" "${C_RED}'swift --version' failed${C_RESET}"
    problems=$((problems + 1))
  elif version_at_least "$SWIFT_VERSION" 6 2; then
    requirement_row ok "Swift $SWIFT_VERSION" "${C_DIM}needs 6.2 or later${C_RESET}"
  else
    requirement_row bad "Swift $SWIFT_VERSION" "${C_RED}Inlay needs Swift 6.2 or later${C_RESET}"
    problems=$((problems + 1))
    notes="${notes}Update the Command Line Tools in System Settings > General > Software Update."$'\n'
  fi

  if command -v codesign >/dev/null 2>&1; then
    requirement_row ok "codesign"
  else
    requirement_row bad "codesign" "${C_RED}not found${C_RESET}"
    problems=$((problems + 1))
  fi

  [ "$problems" -gt 0 ] || return 0
  echo
  if [ "$problems" -eq 1 ]; then
    printf '  %s1 thing to fix before installing:%s\n' "$C_BOLD" "$C_RESET"
  else
    printf '  %s%d things to fix before installing:%s\n' "$C_BOLD" "$problems" "$C_RESET"
  fi
  if [ -n "$fix" ]; then
    echo
    command_box "$fix"
    hint "It opens the installer of Apple (a few minutes). Then run ./install.sh again."
  fi
  printf '%s' "$notes" | while IFS= read -r line; do note "$line"; done
  if [ -n "$fix" ] && is_interactive; then
    echo
    if ask_yes_no "Run it now?" y; then
      xcode-select --install || true
      echo
      hint "Run ./install.sh again when the installer of Apple is done."
    fi
  fi
  exit 1
}

# Sets INSTALL_TARGET, and PREVIOUS_VERSION to the version that is installed there, if any
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
  PREVIOUS_VERSION=""
  if [ -d "$INSTALL_TARGET" ]; then PREVIOUS_VERSION="$(app_version "$INSTALL_TARGET")"; fi
}

# plan_row <number> <what> <where> [<what happens>]. A line of the plan
plan_row() {
  if [ -n "$C_RESET" ]; then
    printf '   %s%s%s  %-16s %s%-34s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2" "$C_DIM" "$3" "$C_RESET" "${4:-}"
  else
    printf '    %s. %-16s %-34s %s\n' "$1" "$2" "$3" "${4:-}"
  fi
}

# What will happen to a config file that exists, for the plan: "<path><TAB><what happens>"
config_file_plan() {
  local config="$1" reset="$2" status
  if [ "$reset" = true ]; then
    status="${C_YELLOW}replaced by the repo's (--reset-config) · yours is kept as a backup${C_RESET}"
  elif [ ! -L "$config" ] && cmp -s "$config" inlay.toml; then
    status="${C_GREEN}up to date${C_RESET}"
  elif [ ! -L "$config" ] && is_known_default_config "$config" scripts/default-config-hashes.txt; then
    status="${C_YELLOW}an old default config: updated · the old one is kept as a backup${C_RESET}"
  else
    status="${C_GREEN}yours, kept${C_RESET}"
  fi
  printf '%s\t%s\n' "$(pretty_path "$config")" "$status"
}

# What will happen to the config, for the plan: "<path><TAB><what happens>". Changes nothing. See ensure_config
config_plan() {
  local import="$1" reset="$2" dir xdg dotfile
  dir="$(config_home)/inlay"
  xdg="$dir/inlay.toml"
  dotfile="$HOME/.inlay.toml"
  if path_exists "$dotfile" && path_exists "$xdg"; then
    printf '%s\t%s\n' "$(pretty_path "$dotfile")" "${C_YELLOW}and $(pretty_path "$xdg"): two configs${C_RESET}"
  elif path_exists "$dotfile"; then
    config_file_plan "$dotfile" "$reset"
  elif [ -L "$dir" ] && [ "$reset" = true ]; then
    printf '%s\t%s\n' "$(pretty_path "$dir")" "${C_YELLOW}the repo's (--reset-config) · the link is kept as a backup${C_RESET}"
  elif [ -L "$dir" ]; then
    printf '%s\t%s\n' "$(pretty_path "$dir") -> $(pretty_path "$(readlink "$dir")")" "${C_GREEN}yours, kept${C_RESET}"
  elif path_exists "$xdg"; then
    config_file_plan "$xdg" "$reset"
  elif [ "$import" = true ] && aerospace_config >/dev/null; then
    printf '%s\t%s\n' "$(pretty_path "$xdg")" "new: from $(pretty_path "$(aerospace_config)")"
  else
    printf '%s\t%s\n' "$(pretty_path "$xdg")" "new: a copy of the repo's inlay.toml"
  fi
}

# show_plan <signing> <import aerospace> <reset config> <open> <ask: true|false>. Says what is going to happen,
# before anything happens, and asks to go on
show_plan() {
  local signing="$1" import="$2" reset="$3" open_app="$4" ask="$5" status sign cli_dir config
  echo
  printf '  %sThis is what will happen:%s\n' "$C_BOLD" "$C_RESET"

  status=""
  if [ ! -e .build/release ]; then status="${C_DIM}the first build takes a few minutes${C_RESET}"; fi
  plan_row 1 "Build Inlay.app" "Swift $SWIFT_VERSION · release" "$status"
  if [ "$signing" = adhoc ]; then
    sign="${C_YELLOW}ad hoc signature (--adhoc-signing): the Accessibility permission is lost on every rebuild${C_RESET}"
  elif has_signing_identity; then
    sign="${C_DIM}signed with \"$SIGN_IDENTITY_NAME\"${C_RESET} ${C_GREEN}exists${C_RESET}"
  else
    sign="${C_DIM}signed with \"$SIGN_IDENTITY_NAME\": created now, in your login keychain${C_RESET}"
  fi
  # Under the 'where' of the row
  printf '%23s%s\n' "" "$sign"

  if [ -z "$PREVIOUS_VERSION" ] && [ ! -d "$INSTALL_TARGET" ]; then
    status="${C_DIM}new${C_RESET}"
  elif [ "$PREVIOUS_VERSION" = "$REPO_VERSION" ]; then
    status="${C_YELLOW}reinstalls $PREVIOUS_VERSION${C_RESET}"
  else
    status="${C_YELLOW}replaces ${PREVIOUS_VERSION:-the app that is there}${C_RESET}"
  fi
  if inlay_is_running; then status="$status${C_DIM} · quits it first${C_RESET}"; fi
  plan_row 2 "Install" "$(pretty_path "$INSTALL_TARGET")" "$status"

  cli_dir="$(cli_link_dir)"
  status=""
  if ! dir_is_in_path "$cli_dir"; then status="${C_YELLOW}not in your PATH${C_RESET}"; fi
  plan_row 3 "Link the CLI" "$(pretty_path "$cli_dir/$CLI_NAME")" "$status"

  config="$(config_plan "$import" "$reset")"
  plan_row 4 "Your config" "${config%%"$TAB"*}" "${config#*"$TAB"}"

  status=""
  if [ "$open_app" != true ]; then status="${C_DIM}not opened (--no-open)${C_RESET}"; fi
  plan_row 5 "Open Inlay" "" "$status"

  echo
  hint "All the options: ./install.sh --help"
  [ "$ask" = true ] || return 0
  echo
  if ! ask_yes_no "Continue?" y; then
    info "Nothing was done."
    exit 1
  fi
}

# Where the output of the build goes. The 10 most recent logs are kept
start_log() {
  local dir="${INLAY_LOG_DIR:-$HOME/Library/Logs/$APP_NAME}" old
  mkdir -p "$dir"
  LOG_FILE="$dir/install-$(date +%Y%m%d-%H%M%S).log"
  : > "$LOG_FILE"
  # shellcheck disable=SC2012
  ls -1t "$dir"/install-*.log 2>/dev/null | tail -n +11 | while IFS= read -r old; do rm -f "$old"; done
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
  local mode="$1" identity="-" signature
  if [ "$mode" = stable ] && ! ensure_signing_identity; then
    warn "falling back to an ad hoc signature: the Accessibility permission will be lost on every rebuild."
    mode=adhoc
  fi
  if [ "$mode" = stable ]; then identity="$SIGN_IDENTITY_NAME"; fi
  if ! spin_command "$LOG_FILE" scripts/build-app.sh --sign-identity "$identity"; then
    if [ "$VERBOSE" != true ] && [ -n "$C_RESET" ]; then
      problem "The build failed after $(format_duration "$SPIN_SECONDS"). The end of its output:"
      # Without the '[n/m] Compiling …' lines: the errors are what matters
      grep -Ev '^\[[0-9]+/[0-9]+\] ' "$LOG_FILE" | tail -n 25 | sed 's/^/      /' >&2
    fi
    hint "Its whole output: $(pretty_path "$LOG_FILE")" >&2
    hint "To see it as it comes:  ./install.sh --verbose" >&2
    fail "the build failed."
  fi
  # build-app.sh falls back to an ad hoc signature on its own when codesign can't use the identity.
  # Not a pipe into 'grep -q': with pipefail, grep leaving early makes the pipe fail
  signature="$(codesign --display --verbose "build/$APP_NAME.app" 2>&1 || true)"
  case "$signature" in
    *Signature=adhoc*) SIGNED_WITH=adhoc ;;
    *) SIGNED_WITH=stable ;;
  esac
  if [ "$SIGNED_WITH" = stable ]; then
    ok "Built $APP_NAME.app ${C_DIM}· signed with \"$SIGN_IDENTITY_NAME\" · $(format_duration "$SPIN_SECONDS")${C_RESET}"
  else
    ok "Built $APP_NAME.app ${C_DIM}· ad hoc signature · $(format_duration "$SPIN_SECONDS")${C_RESET}"
    if [ "$mode" = stable ]; then
      warn "codesign could not use \"$SIGN_IDENTITY_NAME\": the app has an ad hoc signature, and the"
      warn "Accessibility permission will be lost on every rebuild. Details: $(pretty_path "$LOG_FILE")"
    fi
  fi
}

install_app() {
  quit_running_inlay
  rm -rf "$INSTALL_TARGET"
  ditto "build/$APP_NAME.app" "$INSTALL_TARGET"
  # Tells Finder and Launch Services that the bundle changed
  touch "$INSTALL_TARGET"
  "$LSREGISTER" -f "$INSTALL_TARGET" >/dev/null 2>&1 || true
  if [ -n "$PREVIOUS_VERSION" ] && [ "$PREVIOUS_VERSION" != "$REPO_VERSION" ]; then
    ok "Installed $(pretty_path "$INSTALL_TARGET") ${C_DIM}· it was $PREVIOUS_VERSION${C_RESET}"
  else
    ok "Installed $(pretty_path "$INSTALL_TARGET")"
  fi
}

# Prints the directory where the CLI is linked: INLAY_BIN_DIR, or the first candidate that is writable and
# already in the PATH, or ~/.local/bin. Changes nothing
cli_link_dir() {
  local candidate
  if [ -n "${INLAY_BIN_DIR:-}" ]; then
    printf '%s\n' "$INLAY_BIN_DIR"
    return 0
  fi
  while IFS= read -r candidate; do
    if [ -d "$candidate" ] && [ -w "$candidate" ] && dir_is_in_path "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done <<LIST
$(cli_dir_candidates)
LIST
  printf '%s\n' "$HOME/.local/bin"
}

# Sets CLI_LINK to the link, or to nothing if it wasn't linked
link_cli() {
  local dir link source="$INSTALL_TARGET/$CLI_PATH_IN_APP"
  CLI_LINK=""
  dir="$(cli_link_dir)"
  mkdir -p "$dir" 2>/dev/null || true
  [ -d "$dir" ] && [ -w "$dir" ] || { warn "$dir is not writable: the '$CLI_NAME' CLI was not linked."; return 0; }

  link="$dir/$CLI_NAME"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    warn "$link exists and is not a symlink: leaving it alone. The CLI is at $source"
    return 0
  fi
  ln -sfn "$source" "$link"
  CLI_LINK="$link"
  ok "Linked $(pretty_path "$link") ${C_MAGENTA}->${C_RESET} $(pretty_path "$source")"
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

# toml_settings <file>. The settings of a TOML config, one per line: "<id><TAB><[table]><TAB><key = value>". The
# id of a key binding is its command, not its key: a binding that a config has under another key is not missing.
# The rules ([[on-window-detected]]) are not settings, and they are left out
toml_settings() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    depth > 0 { depth += gsub(/\[/, "[") - gsub(/\]/, "]"); next }
    /^[ \t]*(#|$)/ { next }
    /^[ \t]*\[\[/ { rules = 1; next }
    /^[ \t]*\[/ { t = $0; sub(/^[ \t]*\[/, "", t); sub(/\].*$/, "", t); table = trim(t); rules = 0; next }
    rules { next }
    {
      eq = index($0, "=")
      if (eq == 0) next
      key = trim(substr($0, 1, eq - 1))
      value = trim(substr($0, eq + 1))
      sub(/[ \t]+#.*$/, "", value)
      gsub(/["\047 \t]/, "", key)
      v = value
      opened = gsub(/\[/, "[", v)
      closed = gsub(/\]/, "]", v)
      if (opened > closed) { depth = opened - closed; value = value " ..." }
      id = value
      gsub(/["\047 \t]/, "", id)
      id = (table ~ /\.binding$/) ? table "=" id : table "." key
      print id "\t" (table == "" ? "(top level)" : "[" table "]") "\t" key " = " value
    }' "$1"
}

# missing_settings <config> <reference>. The settings of the reference that the config doesn't have:
# "<[table]><TAB><key = value>", one per line
missing_settings() {
  awk -F "$TAB" 'NR == FNR { have[$1] = 1; next } !($1 in have) { print $2 "\t" $3 }' \
    <(toml_settings "$1") <(toml_settings "$2")
}

show_config_diff() {
  { diff -u "$1" inlay.toml || true; } | if command -v less >/dev/null 2>&1; then less -R; else cat; fi
}

# config_differences <config> <can be replaced: true|false>. The config is kept as it is: says what the inlay.toml
# of the repo has that it doesn't. On a terminal, offers to show the whole diff and, unless the config is in a
# linked folder, to switch to the inlay.toml of the repo (the config is kept as a backup)
config_differences() {
  local config="$1" can_replace="$2" missing count table setting
  if [ ! -e "$config" ]; then
    warn "It is a symbolic link to a file that doesn't exist: Inlay can't read it."
    return 0
  fi
  missing="$(missing_settings "$config" inlay.toml)"
  count="$(printf '%s' "$missing" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    hint "It has every setting of the inlay.toml of the repo (the values may differ)."
  else
    if [ "$count" -eq 1 ]; then
      note "${C_BOLD}The inlay.toml of the repo has 1 setting that yours doesn't:${C_RESET}"
    else
      note "${C_BOLD}The inlay.toml of the repo has $count settings that yours doesn't:${C_RESET}"
    fi
    printf '%s\n' "$missing" | sed -n '1,8p' | while IFS="$TAB" read -r table setting; do
      printf '      %s+%s %s%-22s%s %s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$table" "$C_RESET" "$setting"
    done
    if [ "$count" -gt 8 ]; then hint "  ... and $((count - 8)) more"; fi
  fi
  if ! grep -Eq '^[[:space:]]*\[\[on-window-detected\]\]' "$config"; then
    warn "It has no [[on-window-detected]] rule: no window is sent to a workspace, they all stay in the"
    warn "workspace where they open."
  fi
  [ "$count" -gt 0 ] || return 0

  if [ "$CAN_ASK" != true ]; then
    hint "To switch to the inlay.toml of the repo (yours is kept as a backup):  ./install.sh --reset-config"
    hint "To compare them:  diff \"$config\" \"$PWD/inlay.toml\""
    return 0
  fi
  while true; do
    echo
    if [ "$can_replace" = true ]; then
      choose_one "What now?" "↑↓ · Enter" "Keep yours${TAB}nothing changes" "Show the whole diff${TAB}yours, then the repo's" \
        "Use the repo's inlay.toml${TAB}yours is kept as a backup"
    else
      choose_one "What now?" "↑↓ · Enter" "Keep yours${TAB}it is in a folder of yours: edit it there" \
        "Show the whole diff${TAB}yours, then the repo's"
    fi
    case "$CHOICE" in
      1) return 0 ;;
      2) show_config_diff "$config" ;;
      3)
        replace_config "$config"
        ok "Switched to the inlay.toml of the repo: $(pretty_path "$config")"
        note "Yours is kept as $(pretty_path "$CONFIG_BACKUP")"
        return 0
        ;;
    esac
  done
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
    ok "You already have a config: $(pretty_path "$config") ${C_DIM}· the inlay.toml of the repo, up to date${C_RESET}"
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
    ok "You already have a config: $(pretty_path "$config") ${C_MAGENTA}->${C_RESET} $(pretty_path "$target") ${C_DIM}· yours, kept${C_RESET}"
  else
    ok "You already have a config: $(pretty_path "$config") ${C_DIM}· yours, kept${C_RESET}"
  fi
  config_differences "$config" true
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

  ok "You already have a config: $(pretty_path "$dir") ${C_MAGENTA}->${C_RESET} $(pretty_path "$target") ${C_DIM}· a linked folder, yours${C_RESET}"
  if [ ! -d "$dir" ]; then
    warn "the folder that $dir points to doesn't exist: Inlay can't read your config, and uses"
    warn "its built-in one until the folder is back."
  elif ! path_exists "$dir/inlay.toml"; then
    warn "$target has no inlay.toml: Inlay uses its built-in config until there is one."
  elif cmp -s "$dir/inlay.toml" inlay.toml; then
    hint "Its inlay.toml is the one of the repo, up to date."
  else
    config_differences "$dir/inlay.toml" false
  fi
}

# ensure_config <import aerospace: true|false> <link: a folder, or empty> <prompt: true|false> <reset: true|false>
# Creates the config when there is none. An existing one is only replaced when it is a default config of a
# previous version, or when --reset-config (or the user, when asked) wants it, and it is always kept as a backup.
# See "Your config". Then the config folder can become a symbolic link to a folder of the user. See "Your own
# config folder". Sets CONFIG_PATH to the config that Inlay will read, or to nothing if it can't tell (two configs)
ensure_config() {
  local import="$1" link="$2" prompt="$3" reset="$4" dir xdg dotfile source
  dir="$(config_home)/inlay"
  xdg="$dir/inlay.toml"
  dotfile="$HOME/.inlay.toml"
  CONFIG_PATH=""
  CONFIG_CREATED=false

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
      ok "Created $(pretty_path "$xdg") ${C_DIM}· a copy of the inlay.toml of the repo${C_RESET}"
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

# link_candidates <config folder> <suggestion, or empty>. The folders to offer in the question, one per line: the
# suggestion and the folders of a dotfiles repo, once each. Not the config folder, nor the folder it is linked to
link_candidates() {
  local dir="$1" suggestion="$2" candidate found=""
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ -d "$dir" ] && [ "$candidate" -ef "$dir" ]; then continue; fi
    case "$(printf '\n%s\n' "$found")" in *$'\n'"$candidate"$'\n'*) continue ;; esac
    found="$found$candidate"$'\n'
  done <<LIST
$suggestion
$(config_folder_candidates)
LIST
  printf '%s' "$found"
}

# check_link_target <config folder> <folder> <link now: a folder, or empty> <a folder without inlay.toml: ask, copy
# or no>. Whether the config folder can be linked to <folder>, saying why not. Returns 0 if it can, 1 if it can't
# and 2 if it already is. A folder without inlay.toml gets the one of the repo: if the user says so (ask), or
# without asking (copy: the user picked it in a list that said so)
check_link_target() {
  local dir="$1" target="$2" current="$3" missing_toml="$4" pretty
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
  if [ "$missing_toml" = copy ]; then
    cp inlay.toml "$target/inlay.toml"
    ok "Copied the inlay.toml of the repo to $pretty/inlay.toml"
    return 0
  fi
  warn "$pretty has no inlay.toml."
  if [ "$missing_toml" = ask ]; then
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

# choose_config_folder <config folder> <link now, or empty> <the folders of the list>. Asks for the path of the
# folder to link until it gets one that can be linked, or nothing. Sets CHOSEN_FOLDER. Returns 1 if nothing is to
# be linked and 2 if the config folder already is linked to the folder
choose_config_folder() {
  local dir="$1" current="$2" found="$3" target candidate status
  CHOSEN_FOLDER=""
  while true; do
    ask_path "Folder" "Tab completes · Enter with nothing keeps your config"
    [ -n "$ANSWER" ] || return 1
    target="$(absolute_path "$ANSWER" "$START_DIR")"
    # Without the trailing slashes: the link is to the folder. Tab leaves one after the name of a folder
    while [ "$target" != / ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done
    status=0
    check_link_target "$dir" "$target" "$current" ask || status=$?
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

# A few words about the config that is in use now, for the first option of the question
config_summary() {
  if [ "$CONFIG_CREATED" = true ]; then
    printf 'new: a copy of the repo'"'"'s inlay.toml\n'
  elif [ -f "$CONFIG_PATH" ]; then
    printf 'where it is now · %s lines\n' "$(wc -l < "$CONFIG_PATH" | tr -d ' ')"
  else
    printf 'where it is now\n'
  fi
}

# link_config_folder <config folder> <link: a folder, or empty> <prompt: true|false>
# Makes the config folder a symbolic link to a folder of the user: the one of --config-link, or the one that the
# user picks in the question, which is asked on every run. See "Your own config folder".
# A real config folder is never deleted (it is renamed), and nothing is written to the folder of the user
# without asking
link_config_folder() {
  local dir="$1" target="$2" prompt="$3" current="" legacy="" suggestion="" found candidate detail backup status=0
  local options
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
    if [ -n "$current" ]; then
      options=("Keep the link${TAB}$(pretty_path "$dir") -> $(pretty_path "$current")")
    else
      hint "$(pretty_path "$dir") can also be a link to a folder of yours (a dotfiles repo, for example)."
      if [ -n "$legacy" ]; then
        hint "Right now only the file is linked, the way a previous version did it:"
        hint "$(pretty_path "$dir/inlay.toml") -> $(pretty_path "$legacy")"
        # The folder that holds the linked file is the obvious one to link, if the file has the name Inlay looks for
        if [ "$(basename "$legacy")" = inlay.toml ]; then
          suggestion="$(dirname "$(absolute_path "$legacy" "$dir")")"
        fi
      fi
      options=("Keep $(pretty_path "$dir")${TAB}$(config_summary)")
    fi
    found="$(link_candidates "$dir" "$suggestion")"
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if path_exists "$candidate/inlay.toml"; then
        detail="has inlay.toml"
      else
        detail="no inlay.toml: gets a copy of the repo's"
      fi
      options[${#options[@]}]="Link $(pretty_path "$candidate")${TAB}$detail"
    done <<LIST
$found
LIST
    options[${#options[@]}]="Another folder...${TAB}type its path"

    choose_one "Where should your config live?" "↑↓ · Enter" "${options[@]}"
    if [ "$CHOICE" -eq 1 ]; then
      return 0
    elif [ "$CHOICE" -eq "${#options[@]}" ]; then
      choose_config_folder "$dir" "$current" "$found" || status=$?
      target="$CHOSEN_FOLDER"
    else
      target="$(printf '%s' "$found" | sed -n "$((CHOICE - 1))p")"
      check_link_target "$dir" "$target" "$current" copy || status=$?
    fi
  else
    target="$(absolute_path "$target" "$START_DIR")"
    # Without the trailing slashes: the link is to the folder
    while [ "$target" != / ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done
    check_link_target "$dir" "$target" "$current" "$([ "$prompt" = true ] && is_interactive && echo ask || echo no)" ||
      status=$?
  fi
  case "$status" in
    1) nothing_was_linked; return 0 ;;
    2) return 0 ;;
  esac

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
  CONFIG_CREATED=false
  ok "Linked $(pretty_path "$dir") ${C_MAGENTA}->${C_RESET} $(pretty_path "$target")"
  hint "Inlay reads and writes $(pretty_path "$target")/inlay.toml"
}

# Says what the parser of the app that was just installed thinks of the config. Never fails the installation.
# Sets CONFIG_CHECK: ok, warnings, errors, or nothing when there is nothing to check
check_config() {
  local binary="$INSTALL_TARGET/Contents/MacOS/$APP_NAME" output status=0
  CONFIG_CHECK=""
  [ -n "$CONFIG_PATH" ] && [ -x "$binary" ] || return 0
  # A link that leads nowhere, or a linked folder without inlay.toml: there is nothing to check, and it was said
  [ -e "$CONFIG_PATH" ] || return 0
  output="$("$binary" --check-config "$CONFIG_PATH" 2>&1)" || status=$?
  case "$output" in
    *"has no errors or warnings")
      CONFIG_CHECK=ok
      ok "No errors or warnings in $(pretty_path "$CONFIG_PATH")"
      ;;
    *)
      CONFIG_CHECK=warnings
      printf '%s\n' "$output" | sed 's/^/    /'
      ;;
  esac
  if [ "$status" -ne 0 ]; then
    CONFIG_CHECK=errors
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

# Opens Inlay, or says why not. Sets OPEN_STATUS: open, conflict, failed or no-open
open_or_explain() {
  local open_app="$1"
  find_conflicts
  if [ -n "$CONFLICTS" ]; then
    OPEN_STATUS=conflict
    warn "these apps are running and do the same job as Inlay: $CONFLICTS"
    warn "Two window managers at once fight over your windows, so Inlay was NOT opened, and this script"
    warn "doesn't quit other apps for you. Quit them (AeroSpace and AeroMenu from their menu bar icons;"
    warn "borders with 'brew services stop borders' or 'pkill borders'), and then open Inlay with:"
    warn "  open \"$INSTALL_TARGET\""
  elif [ "$open_app" = true ]; then
    if open "$INSTALL_TARGET"; then
      OPEN_STATUS=open
      ok "Opened $APP_NAME ${C_DIM}· it lives in the menu bar: no Dock icon, no window${C_RESET}"
    else
      OPEN_STATUS=failed
      warn "could not open it. Open it by hand:  open \"$INSTALL_TARGET\""
    fi
  else
    OPEN_STATUS=no-open
    hint "Not opened (--no-open). Open it with:  open \"$INSTALL_TARGET\""
  fi
}

# workspace_keys <config>. The keys of the main mode that go to a workspace, the first and the last ones:
# "<key><TAB><workspace><TAB><key><TAB><workspace>", or nothing
workspace_keys() {
  [ -f "$1" ] || return 0
  awk '
    /^[ \t]*\[/ { main = ($0 ~ /^[ \t]*\[mode\.main\.binding\]/); next }
    main && /^[ \t]*[^#=]+=/ && match($0, /["\047]workspace [^"\047 ]+["\047]/) {
      ws = substr($0, RSTART + 11, RLENGTH - 12)
      if (ws == "next" || ws == "prev" || ws ~ /^-/) next
      key = substr($0, 1, index($0, "=") - 1)
      gsub(/[ \t"\047]/, "", key)
      if (first == "") { first = key; first_ws = ws }
      last = key; last_ws = ws
    }
    END { if (first != "") print first "\t" first_ws "\t" last "\t" last_ws }' "$1"
}

# summary_row <name> <value> <ok|warn|bad|none> <status>. A line of the summary
summary_row() {
  local mark=""
  if [ -n "$C_RESET" ]; then
    case "$3" in
      ok) mark="${C_GREEN}✓$C_RESET" ;;
      warn) mark="$C_YELLOW!$C_RESET" ;;
      bad) mark="${C_RED}✗$C_RESET" ;;
      *) mark=" " ;;
    esac
    printf '%s│%s  %s%-8s%s %-38s %s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$1" "$C_RESET" "$2" "$mark" "$C_DIM" "$4" \
      "$C_RESET"
  else
    printf '    %-8s %-38s %s\n' "$1" "$2" "$4"
  fi
}

# next_row <what to do> <what it does>. A line of what to do next
next_row() {
  printf '    %s%-36s%s %s\n' "$C_CYAN" "$1" "$C_RESET" "$2"
}

# The end: where everything is, and what to do now
summary() {
  local config_value config_dir state status first first_ws last last_ws keys
  echo
  if [ -n "$C_RESET" ]; then
    printf '%s╭─%s %s%s %s is installed%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD$C_GREEN" "$APP_NAME" "$REPO_VERSION" "$C_RESET"
    printf '%s│%s\n' "$C_GREEN" "$C_RESET"
  else
    success "$APP_NAME $REPO_VERSION is installed"
  fi

  if [ "$SIGNED_WITH" = stable ]; then
    summary_row App "$(pretty_path "$INSTALL_TARGET")" ok "stable signature"
  else
    summary_row App "$(pretty_path "$INSTALL_TARGET")" warn "ad hoc signature"
  fi

  if [ -z "$CLI_LINK" ]; then
    summary_row CLI "-" warn "not linked: see above"
  elif dir_is_in_path "$(dirname "$CLI_LINK")"; then
    summary_row CLI "$(pretty_path "$CLI_LINK")" ok "in your PATH"
  else
    summary_row CLI "$(pretty_path "$CLI_LINK")" warn "not in your PATH: see above"
  fi

  config_dir="$(config_home)/inlay"
  if [ -z "$CONFIG_PATH" ]; then
    config_value="-"
  elif [ -L "$config_dir" ] && [ "$CONFIG_PATH" = "$config_dir/inlay.toml" ]; then
    config_value="$(pretty_path "$config_dir") -> $(pretty_path "$(readlink "$config_dir")")"
  else
    config_value="$(pretty_path "$CONFIG_PATH")"
  fi
  case "$CONFIG_CHECK" in
    ok) state=ok status="no errors or warnings" ;;
    warnings) state=warn status="warnings: see above" ;;
    errors) state=bad status="errors: see above" ;;
    *)
      if [ -z "$CONFIG_PATH" ]; then state=warn status="two configs: see above"
      else state=warn status="not readable: Inlay uses its built-in one"; fi
      ;;
  esac
  summary_row Config "$config_value" "$state" "$status"

  case "$OPEN_STATUS" in
    open) summary_row Inlay "running, in the menu bar" ok "" ;;
    conflict) summary_row Inlay "not opened" warn "$CONFLICTS running: see above" ;;
    failed) summary_row Inlay "not opened" warn "see above" ;;
    *) summary_row Inlay "not opened" none "--no-open" ;;
  esac
  if [ -n "$C_RESET" ]; then
    printf '%s│%s\n' "$C_GREEN" "$C_RESET"
    printf '%s╰%s%s\n' "$C_GREEN" "$(printf '%*s' 56 '' | sed 's/ /─/g')" "$C_RESET"
  fi

  echo
  printf '  %sNext%s\n' "$C_BOLD" "$C_RESET"
  keys="$(workspace_keys "${CONFIG_PATH:-}")"
  if [ -n "$keys" ]; then
    IFS="$TAB" read -r first first_ws last last_ws <<KEYS
$keys
KEYS
    if [ "$first" = "$last" ]; then
      next_row "$first" "go to workspace $first_ws"
    else
      next_row "$first ... $last" "go to workspaces $first_ws to $last_ws"
    fi
  fi
  next_row "$CLI_NAME config --explain" "every setting, documented"
  next_row "right-click its menu bar item" "the menu and the Settings"
  next_row "the first time it runs" "turn it on in System Settings > Privacy & Security > Accessibility"
  if [ "$SIGNED_WITH" = adhoc ]; then
    next_row "after every rebuild" "remove it from that list (-) and turn it on again (ad hoc signature)"
  fi
  echo
  hint "Took $(format_duration $((SECONDS - START_SECONDS))) · build log $(pretty_path "$LOG_FILE") · to uninstall: $CLI_NAME uninstall"
}

main() {
  local open_app=true signing=stable import=false config_link="" prompt=true reset_config=false assume_yes=false
  VERBOSE=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-open) open_app=false ;;
      --stable-signing) signing=stable ;;
      --adhoc-signing) signing=adhoc ;;
      --import-aerospace) import=true ;;
      --no-prompt) prompt=false ;;
      --reset-config) reset_config=true ;;
      -y|--yes) assume_yes=true ;;
      --verbose) VERBOSE=true ;;
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

  START_SECONDS="$SECONDS"
  REPO_VERSION="$(tr -d '[:space:]' < VERSION)"
  CAN_ASK=false
  if [ "$prompt" = true ] && is_interactive; then CAN_ASK=true; fi

  print_header
  check_requirements
  choose_install_dir
  show_plan "$signing" "$import" "$reset_config" "$open_app" \
    "$([ "$CAN_ASK" = true ] && [ "$assume_yes" != true ] && echo true || echo false)"

  STEP_TOTAL=5
  start_log
  step "Build $APP_NAME.app"
  build_app "$signing"
  step "Install"
  install_app
  step "Link the CLI"
  link_cli
  step "Your config"
  ensure_config "$import" "$config_link" "$prompt" "$reset_config"
  check_config
  step "Open $APP_NAME"
  open_or_explain "$open_app"
  summary
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
