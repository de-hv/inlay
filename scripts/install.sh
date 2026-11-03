#!/usr/bin/env bash
#
# Builds Inlay, installs it and opens it. Needs only the Xcode Command Line Tools: no Xcode, no Apple ID.
# No option is needed:
#
#   ./install.sh
#
# On a terminal every step is a line of a list, from the start, in three groups (Prepare, Install, Configure),
# marked in place as it goes: '·' while it waits, a spinner while it runs (the build with a bar), then '✓' (or '!'
# or '✗') and a short detail. The long values (the commit, the version of the compiler) only go to the log. What
# doesn't fit in a line (a backup that was made, a warning) is said below the list when it is done. Elsewhere,
# and with --verbose, it is plain text. With 24-bit colors (COLORTERM=truecolor) it uses the colors of Material 3.
# First it checks the requirements, all of them, and shows how to fix what is missing. Then the list says what
# every step is going to do (where it installs, what happens to your config) and asks to go on: Enter installs,
# Esc cancels. Then:
#   1. builds Inlay.app and signs it with a local identity, so that macOS keeps the Accessibility permission
#      across rebuilds (see "Signing" below). Its line says how far the build is: its whole output goes to
#      ~/Library/Logs/Inlay/install-<date>.log (--verbose shows it as it comes);
#   2. installs it into /Applications (or ~/Applications if /Applications isn't writable);
#   3. links the 'inlay' CLI into ~/.local/bin, /opt/homebrew/bin or /usr/local/bin;
#   4. creates ~/.config/inlay/inlay.lua from the inlay.lua of the repo if you have no Inlay config yet
#      (what happens to a config that you already have: see "Your config" below), and asks, every time, where
#      your config should live, in a menu right below its line: where it is, the inlay.lua of the repo, or a
#      folder of your own through a symbolic link (see "Your own config folder" below). Enter keeps what you have;
#   5. opens Inlay. The last lines say what to do the first time (the Accessibility permission).
# Running it again updates the installed app: the running copy is quit first.
#
# Your config: a config that you already have is yours, and it is never edited, replaced or deleted without
# asking. With one exception: a config that is identical, byte for byte, to a default config that a previous
# version of Inlay installed (scripts/default-config-hashes.txt) was never edited by anybody, so it is replaced
# by the current inlay.lua, and the old one is kept next to it as a backup (inlay.lua.backup-<date>). Any other
# config is kept as it is, and its line says whether it differs from the inlay.lua of the repo. On a terminal
# the menu of the question can switch to the inlay.lua of the repo (yours is kept as a backup), and 'd' shows
# the diff. --reset-config is how you switch without being asked.
#
# The config of Inlay 0.2, inlay.toml, isn't read by Inlay 0.3, whose config is Lua. A default inlay.toml that
# nobody edited is replaced by the inlay.lua of the repo (and kept as inlay.toml.backup-<date>). Any other one
# stays where it is and its line says that it isn't read: write your config in Lua as inlay.lua, next to it,
# starting from the inlay.lua of the repo (the menu of the question can copy it there).
#
# Your own config folder: the question lists the folders of a dotfiles repo that it finds (~/.dotfiles/inlay,
# ~/dotfiles/inlay…): pick one with the arrows, or "Another folder..." to type a path (Tab completes it).
# ~/.config/inlay becomes a symbolic link to that folder. Inlay reads the inlay.lua in it, and the files of the
# folder that inlay.lua requires; nothing else of the folder is touched.
#   - A folder of the list without inlay.lua gets a copy of the inlay.lua of the repo.
#   - A typed folder that doesn't exist, or can't be linked: the script says why and asks again. Enter with
#     nothing keeps your config as it is. A typed folder without inlay.lua: the script asks whether to copy
#     the inlay.lua of the repo into it. If you say no, it asks for another folder.
#   - You already had a real ~/.config/inlay: it is not deleted. It is renamed to ~/.config/inlay.backup-<date>.
#   - ~/.config/inlay already is a link: the first option keeps it. Linking another folder only replaces the
#     link: the folder it pointed to is not touched.
#   - A previous version linked the file instead (~/.config/inlay/inlay.toml -> your file). It is left alone;
#     the folder that holds that file is in the list, to link it instead.
# A linked folder is yours: its files are never replaced, not even when they are identical to an old default
# config.
#
# Options (none of them is needed):
#   --config-link <folder> link ~/.config/inlay to <folder> without asking, with the same rules as above. A
#                          folder without inlay.lua is only filled in if there is a terminal to ask on
#   -y, --yes              don't ask before starting. The questions about the config are still asked
#   --no-prompt            don't ask anything: keep the config as it is. It's what happens on its own when
#                          there is no terminal to ask on
#   --reset-config         replace your config by the inlay.lua of the repo, whatever is in it. Your config is
#                          kept next to it as a backup (<file>.backup-<date>). Nothing that a symbolic link
#                          points to is ever written, moved or deleted: with a linked folder, the link itself is
#                          renamed to ~/.config/inlay.backup-<date> and ~/.config/inlay becomes a real folder
#                          with the inlay.lua of the repo; with a linked file, the link becomes the backup
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

# The header: 'Inlay 0.1.0  installer'. The commit is only in the plain output and in the log
print_header() {
  local hash
  hash="$(git rev-parse --short HEAD 2>/dev/null || echo SNAPSHOT)"
  if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then hash="$hash-dirty"; fi
  if [ -n "$C_RESET" ]; then
    # The first group of the list brings its own empty line
    printf '\n  %s%s %s%s  %sinstaller%s\n' "$C_BOLD" "$APP_NAME" "$REPO_VERSION" "$C_RESET" "$C_DIM" "$C_RESET"
  else
    printf '==> %s %s installer (%s)\n' "$APP_NAME" "$REPO_VERSION" "$hash"
  fi
}

# The steps, in the order of the list, and their groups. See: checklist_start, checklist_groups
S_REQUIREMENTS=0
S_BUILD=1
S_INSTALL=2
S_CLI=3
S_CONFIG=4
S_OPEN=5

# Checks every requirement, not only up to the first one that is missing. Sets SWIFT_VERSION, and REQ_ROWS,
# REQ_PROBLEMS, REQ_FIX and REQ_NOTES for explain_requirements. Returns 1 if something is missing
check_requirements() {
  local macos
  SWIFT_VERSION=""
  REQ_ROWS="" REQ_PROBLEMS=0 REQ_FIX="" REQ_NOTES=""
  REQ_MACOS="$(sw_vers -productVersion)"
  macos="$REQ_MACOS"
  if version_at_least "$macos" 14 0; then
    REQ_ROWS="$REQ_ROWS$(requirement_row ok "macOS $macos" "${C_DIM}needs 14 or later${C_RESET}")"$'\n'
  else
    REQ_ROWS="$REQ_ROWS$(requirement_row bad "macOS $macos" "${C_RED}Inlay needs macOS 14 or later${C_RESET}")"$'\n'
    REQ_PROBLEMS=$((REQ_PROBLEMS + 1))
    REQ_NOTES="${REQ_NOTES}Update macOS in System Settings > General > Software Update, if this Mac supports macOS 14."$'\n'
  fi

  if [ "${INLAY_USE_SELECTED_TOOLCHAIN:-0}" = 1 ]; then
    if command -v swift >/dev/null 2>&1; then
      REQ_ROWS="$REQ_ROWS$(requirement_row ok "Selected toolchain" "${C_DIM}INLAY_USE_SELECTED_TOOLCHAIN=1${C_RESET}")"$'\n'
    else
      REQ_ROWS="$REQ_ROWS$(requirement_row bad "Selected toolchain" "${C_RED}swift was not found${C_RESET}")"$'\n'
      REQ_PROBLEMS=$((REQ_PROBLEMS + 1))
    fi
  elif [ -x "$CLT_DIR/usr/bin/swift" ]; then
    export DEVELOPER_DIR="$CLT_DIR"
    REQ_ROWS="$REQ_ROWS$(requirement_row ok "Command Line Tools" "${C_DIM}$CLT_DIR${C_RESET}")"$'\n'
  else
    REQ_ROWS="$REQ_ROWS$(requirement_row bad "Command Line Tools" "${C_RED}not installed${C_RESET}${C_DIM} · Xcode is not needed${C_RESET}")"$'\n'
    REQ_PROBLEMS=$((REQ_PROBLEMS + 1))
    REQ_FIX="xcode-select --install"
  fi

  if [ -z "$REQ_FIX" ] && command -v swift >/dev/null 2>&1; then SWIFT_VERSION="$(swift_version)"; fi
  if [ -n "$REQ_FIX" ]; then
    REQ_ROWS="$REQ_ROWS$(requirement_row bad "Swift 6.2" "${C_DIM}comes with the Command Line Tools${C_RESET}")"$'\n'
  elif [ -z "$SWIFT_VERSION" ]; then
    REQ_ROWS="$REQ_ROWS$(requirement_row bad "Swift" "${C_RED}'swift --version' failed${C_RESET}")"$'\n'
    REQ_PROBLEMS=$((REQ_PROBLEMS + 1))
  elif version_at_least "$SWIFT_VERSION" 6 2; then
    REQ_ROWS="$REQ_ROWS$(requirement_row ok "Swift $SWIFT_VERSION" "${C_DIM}needs 6.2 or later${C_RESET}")"$'\n'
  else
    REQ_ROWS="$REQ_ROWS$(requirement_row bad "Swift $SWIFT_VERSION" "${C_RED}Inlay needs Swift 6.2 or later${C_RESET}")"$'\n'
    REQ_PROBLEMS=$((REQ_PROBLEMS + 1))
    REQ_NOTES="${REQ_NOTES}Update the Command Line Tools in System Settings > General > Software Update."$'\n'
  fi

  if command -v codesign >/dev/null 2>&1; then
    REQ_ROWS="$REQ_ROWS$(requirement_row ok "codesign")"$'\n'
  else
    REQ_ROWS="$REQ_ROWS$(requirement_row bad "codesign" "${C_RED}not found${C_RESET}")"$'\n'
    REQ_PROBLEMS=$((REQ_PROBLEMS + 1))
  fi
  [ "$REQ_PROBLEMS" -eq 0 ]
}

# Below the list, once it is done: every requirement, how to fix what is missing, and the offer to install the
# Command Line Tools. Then the script ends
explain_requirements() {
  echo
  printf '%s' "$REQ_ROWS"
  echo
  if [ "$REQ_PROBLEMS" -eq 1 ]; then
    printf '  %s1 thing to fix before installing:%s\n' "$C_BOLD" "$C_RESET"
  else
    printf '  %s%d things to fix before installing:%s\n' "$C_BOLD" "$REQ_PROBLEMS" "$C_RESET"
  fi
  if [ -n "$REQ_FIX" ]; then
    echo
    command_box "$REQ_FIX"
    hint "It opens the installer of Apple (a few minutes). Then run ./install.sh again."
  fi
  printf '%s' "$REQ_NOTES" | while IFS= read -r line; do note "$line"; done
  if [ -n "$REQ_FIX" ] && is_interactive; then
    echo
    if ask_yes_no "Run it now?" y; then
      xcode-select --install || true
      echo
      hint "Run ./install.sh again when the installer of Apple is done."
    fi
  fi
  exit 1
}

# What will happen to the config, for its line in the list before anything happens. Changes nothing. See config_step
config_plan() {
  local reset="$1" dir xdg dotfile legacy replaced
  dir="$(config_home)/inlay"
  xdg="$dir/inlay.lua"
  dotfile="$HOME/.inlay.lua"
  legacy="$dir/inlay.toml"
  replaced="$([ "$reset" = true ] && echo " · replaced by the repo's (--reset-config)")"
  if path_exists "$dotfile" && path_exists "$xdg"; then
    printf '%s and %s · two configs\n' "$(pretty_path "$dotfile")" "$(pretty_path "$xdg")"
  elif path_exists "$dotfile"; then
    printf '%s\n' "$(pretty_path "$dotfile")"
  elif [ -L "$dir" ]; then
    printf '%s → %s%s\n' "$(pretty_path "$dir")" "$(pretty_path "$(readlink "$dir")")" "$replaced"
  elif path_exists "$xdg"; then
    printf '%s%s\n' "$(pretty_path "$xdg")" "$replaced"
  elif path_exists "$legacy"; then
    printf '%s · Inlay 0.2%s\n' "$(pretty_path "$legacy")" "$replaced"
  elif path_exists "$HOME/.inlay.toml"; then
    printf '%s · Inlay 0.2%s\n' "$(pretty_path "$HOME/.inlay.toml")" "$replaced"
  else
    printf '%s · new, a copy of the repo'"'"'s\n' "$(pretty_path "$xdg")"
  fi
}

# plan <signing> <reset config> <open>. What every step will do, in the list, before anything is done
plan() {
  local signing="$1" reset="$2" open_app="$3" detail cli_dir
  detail="release"
  if [ "$signing" = adhoc ]; then
    detail="$detail · ad hoc signature"
  elif has_signing_identity; then
    detail="$detail · local signature"
  else
    detail="$detail · creates a local signing identity"
  fi
  if [ ! -e .build/release ]; then detail="$detail · first build: a few minutes"; fi
  CL_DETAILS[S_BUILD]="$detail"

  detail="$(pretty_path "$INSTALL_TARGET")"
  if [ -n "$PREVIOUS_VERSION" ] && [ "$PREVIOUS_VERSION" = "$REPO_VERSION" ]; then
    detail="$detail · reinstall"
  elif [ -n "$PREVIOUS_VERSION" ] || [ -d "$INSTALL_TARGET" ]; then
    detail="$detail · replaces ${PREVIOUS_VERSION:-the app that is there}"
  fi
  if inlay_is_running; then detail="$detail · quits it first"; fi
  CL_DETAILS[S_INSTALL]="$detail"

  cli_dir="$(cli_link_dir)"
  detail="$(pretty_path "$cli_dir/$CLI_NAME")"
  if ! dir_is_in_path "$cli_dir"; then detail="$detail · not in your PATH"; fi
  CL_DETAILS[S_CLI]="$detail"

  CL_DETAILS[S_CONFIG]="$(config_plan "$reset")"
  if [ "$open_app" != true ]; then CL_DETAILS[S_OPEN]="not opened (--no-open)"; fi
  checklist_draw
}

# build_app <stable|adhoc>. Sets SIGNED_WITH to 'stable' or 'adhoc': the signature that the build really got
build_app() {
  local mode="$1" identity="-" signature
  checklist_set "$S_BUILD" run "starting"
  if [ "$mode" = stable ] && ! ensure_signing_identity; then
    warn "Falling back to an ad hoc signature: the Accessibility permission will be lost on every rebuild."
    mode=adhoc
  fi
  if [ "$mode" = stable ]; then identity="$SIGN_IDENTITY_NAME"; fi
  CL_SPIN="$S_BUILD"
  if ! spin_command "$LOG_FILE" scripts/build-app.sh --sign-identity "$identity"; then
    checklist_set "$S_BUILD" bad "failed after $(format_duration "$SPIN_SECONDS")"
    checklist_end
    if [ "$VERBOSE" != true ] && [ -n "$C_RESET" ]; then
      echo
      printf '  %sThe end of the output of the build:%s\n' "$C_BOLD" "$C_RESET" >&2
      # Without the '[n/m] Compiling …' lines: the errors are what matters
      grep -Ev '^\[[0-9]+/[0-9]+\] ' "$LOG_FILE" | tail -n 25 | sed 's/^/      /' >&2
    fi
    hint "Its whole output: $(pretty_path "$LOG_FILE")" >&2
    hint "To see it as it comes:  ./install.sh --verbose" >&2
    exit 1
  fi
  # build-app.sh falls back to an ad hoc signature on its own when codesign can't use the identity.
  # Not a pipe into 'grep -q': with pipefail, grep leaving early makes the pipe fail
  signature="$(codesign --display --verbose "build/$APP_NAME.app" 2>&1 || true)"
  case "$signature" in
    *Signature=adhoc*) SIGNED_WITH=adhoc ;;
    *) SIGNED_WITH=stable ;;
  esac
  if [ "$SIGNED_WITH" = stable ]; then
    checklist_set "$S_BUILD" ok "signed · $(format_duration "$SPIN_SECONDS")"
  else
    checklist_set "$S_BUILD" warn "ad hoc signature · $(format_duration "$SPIN_SECONDS")"
    if [ "$mode" = stable ]; then
      warn "codesign could not use \"$SIGN_IDENTITY_NAME\": the app has an ad hoc signature, and the Accessibility"
      warn "permission will be lost on every rebuild. Details: $(pretty_path "$LOG_FILE")"
    else
      warn "Ad hoc signature: the Accessibility permission will be lost on every rebuild."
    fi
  fi
}

install_app() {
  local detail
  checklist_set "$S_INSTALL" run
  quit_running_inlay
  rm -rf "$INSTALL_TARGET"
  ditto "build/$APP_NAME.app" "$INSTALL_TARGET"
  # Tells Finder and Launch Services that the bundle changed
  touch "$INSTALL_TARGET"
  "$LSREGISTER" -f "$INSTALL_TARGET" >/dev/null 2>&1 || true
  detail="$(pretty_path "$INSTALL_TARGET")"
  if [ -n "$PREVIOUS_VERSION" ] && [ "$PREVIOUS_VERSION" != "$REPO_VERSION" ]; then detail="$detail · it was $PREVIOUS_VERSION"; fi
  checklist_set "$S_INSTALL" ok "$detail"
}

# Sets CLI_LINK to the link, or to nothing if it wasn't linked
link_cli() {
  local dir link source="$INSTALL_TARGET/$CLI_PATH_IN_APP"
  CLI_LINK=""
  checklist_set "$S_CLI" run
  dir="$(cli_link_dir)"
  mkdir -p "$dir" 2>/dev/null || true
  if [ ! -d "$dir" ] || [ ! -w "$dir" ]; then
    checklist_set "$S_CLI" warn "not linked: $(pretty_path "$dir") isn't writable"
    warn "The '$CLI_NAME' CLI is at $source"
    return 0
  fi
  link="$dir/$CLI_NAME"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    checklist_set "$S_CLI" warn "not linked: $(pretty_path "$link") is a file of its own"
    warn "$link exists and is not a symlink: it was left alone. The '$CLI_NAME' CLI is at $source"
    return 0
  fi
  ln -sfn "$source" "$link"
  CLI_LINK="$link"
  if dir_is_in_path "$dir"; then
    checklist_set "$S_CLI" ok "$(pretty_path "$link")"
  else
    checklist_set "$S_CLI" warn "$(pretty_path "$link") · not in your PATH"
    warn "$dir is not in your PATH. Add this line to ~/.zshrc:  export PATH=\"$dir:\$PATH\""
  fi
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

# replace_config <config> [<new config>]. Puts the inlay.lua of the repo in the place of the config (or at <new
# config>: the inlay.lua that takes the place of an inlay.toml). The config is renamed, not copied: if it is a
# symbolic link, it is the link that becomes the backup, and the file it points to is never written, moved or
# deleted. Sets CONFIG_BACKUP
replace_config() {
  local config="$1" new="${2:-$1}"
  CONFIG_BACKUP="$(backup_path "$config")"
  mv "$config" "$CONFIG_BACKUP"
  cp inlay.lua "$new"
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

# ~~~ Your config ~~~

# What the config step found and did: the line of the step, and its mark
CONFIG_DETAIL=""
CONFIG_STATE=ok
# Whether the config differs from the inlay.lua of the repo. And whether the config can give way to that inlay.lua
# (not when it is in a folder of the user, or when it is the copy that was just made)
CONFIG_DIFFERS=false
CONFIG_REPLACEABLE=false
# An inlay.toml of Inlay 0.2 that stays: CONFIG_LEGACY_PATH, and the inlay.lua that can take its place
CONFIG_LEGACY=false
CONFIG_LEGACY_PATH=""
CONFIG_NEW_PATH=""

# say_problem <text>. A problem with an answer, right below the question
say_problem() {
  if [ "$CL_ACTIVE" = true ]; then checklist_print "      ${C_RED}✗$C_RESET $*"; else problem "$*"; fi
}

say_hint() {
  if [ "$CL_ACTIVE" = true ]; then checklist_print "        $C_DIM$*$C_RESET"; else hint "$*"; fi
}

# What 'd' shows: the diff between the config and the inlay.lua of the repo
show_config_differences() {
  local config="$1"
  printf '%sThe diff: yours, then the inlay.lua of the repo%s\n\n' "$C_BOLD" "$C_RESET"
  diff -u "$config" inlay.lua || true
}

# config_kept <config> <label>. A config that stays as it is: sets CONFIG_DETAIL and CONFIG_DIFFERS
config_kept() {
  local config="$1" label="$2"
  CONFIG_DIFFERS=false
  if [ ! -e "$config" ]; then
    CONFIG_STATE=warn
    CONFIG_DETAIL="$label · leads nowhere"
    warn "$(pretty_path "$config") is a symbolic link to a file that doesn't exist: Inlay uses its built-in config."
    return 0
  fi
  if cmp -s "$config" inlay.lua; then
    CONFIG_DETAIL="$label · up to date"
    return 0
  fi
  CONFIG_DIFFERS=true
  CONFIG_DETAIL="$label · yours"
  # The rules may be in a file that inlay.lua requires
  if ! grep -qs onWindowDetected "$(dirname "$config")"/*.lua; then
    warn "Your config has no onWindowDetected rule: every window stays in the workspace where it opens."
  fi
  if [ "$CAN_ASK" != true ]; then
    hint "How yours differs from the inlay.lua of the repo:  diff \"$config\" \"$PWD/inlay.lua\""
    hint "To switch to it (yours is kept as a backup):  ./install.sh --reset-config"
  fi
}

# config_file <config> <reset: true|false>. A config file that is already there: ~/.config/inlay/inlay.lua in a
# real folder, or ~/.inlay.lua. Only replaced with --reset-config, or when it is a default config of a previous
# version that nobody edited, and then it is kept as a backup. See "Your config"
config_file() {
  local config="$1" reset="$2" label target=""
  label="$(pretty_path "$config")"
  if [ -L "$config" ]; then
    target="$(readlink "$config")"
    label="$label → $(pretty_path "$target")"
  fi
  CONFIG_REPLACEABLE=true
  if [ "$reset" = true ]; then
    replace_config "$config"
    CONFIG_DETAIL="$(pretty_path "$config") · the repo's inlay.lua (--reset-config)"
    CONFIG_REPLACEABLE=false
    note "Your previous config is kept as $(pretty_path "$CONFIG_BACKUP")"
    if [ -n "$target" ]; then note "It was a link to $target: only the link was replaced, that file wasn't touched."; fi
    return 0
  fi
  if [ -z "$target" ] && ! cmp -s "$config" inlay.lua && is_known_default_config "$config" scripts/default-config-hashes.txt; then
    replace_config "$config"
    CONFIG_DETAIL="$(pretty_path "$config") · updated: it was an old default config"
    CONFIG_REPLACEABLE=false
    note "It was the default config of a previous version, never edited. The previous one is kept as $(pretty_path "$CONFIG_BACKUP")"
    return 0
  fi
  config_kept "$config" "$label"
}

# config_linked_folder <config folder> <reset: true|false>. The config folder is a symbolic link to a folder of the
# user. Nothing in that folder is ever written, moved or deleted here: at most the link itself is renamed
config_linked_folder() {
  local dir="$1" reset="$2" target
  target="$(readlink "$dir")"
  CONFIG_REPLACEABLE=false
  if [ "$reset" = true ]; then
    CONFIG_BACKUP="$(backup_path "$dir")"
    mv "$dir" "$CONFIG_BACKUP"
    mkdir -p "$dir"
    cp inlay.lua "$dir/inlay.lua"
    CONFIG_DETAIL="$(pretty_path "$dir/inlay.lua") · the repo's inlay.lua (--reset-config)"
    note "$(pretty_path "$dir") was a link to $(pretty_path "$target"): the link is kept as $(pretty_path "$CONFIG_BACKUP"), and that folder wasn't touched."
    return 0
  fi
  if [ ! -d "$dir" ]; then
    CONFIG_STATE=warn
    CONFIG_DETAIL="$(pretty_path "$dir") → $(pretty_path "$target") · the folder doesn't exist"
    warn "Inlay can't read your config, and uses its built-in one until $(pretty_path "$target") is back."
  elif ! path_exists "$dir/inlay.lua" && path_exists "$dir/inlay.toml"; then
    CONFIG_STATE=warn
    CONFIG_DETAIL="$(pretty_path "$dir") → $(pretty_path "$target") · inlay.toml of Inlay 0.2, not read"
    warn "$(pretty_path "$target") has the inlay.toml of Inlay 0.2, which Inlay $REPO_VERSION doesn't read: the config is Lua"
    warn "now, with camelCase keys. Inlay uses its built-in config until the folder has an inlay.lua. Write it there,"
    warn "starting from the inlay.lua of the repo:  cp \"$PWD/inlay.lua\" \"$target/\""
  elif ! path_exists "$dir/inlay.lua"; then
    CONFIG_STATE=warn
    CONFIG_DETAIL="$(pretty_path "$dir") → $(pretty_path "$target") · no inlay.lua"
    warn "Inlay uses its built-in config until $(pretty_path "$target") has an inlay.lua."
  else
    config_kept "$dir/inlay.lua" "$(pretty_path "$dir") → $(pretty_path "$target")"
  fi
}

# config_legacy <inlay.toml> <the inlay.lua that takes its place> <reset: true|false>. The config of Inlay 0.2, and
# no inlay.lua: Inlay doesn't read it. Replaced by the inlay.lua of the repo when it is a default config that nobody
# edited, or with --reset-config, and then kept as a backup. Otherwise it stays, and the menu of the question can
# put the inlay.lua of the repo in its place
config_legacy() {
  local legacy="$1" xdg="$2" reset="$3"
  if [ "$reset" = true ] || { [ ! -L "$legacy" ] && is_known_default_config "$legacy" scripts/default-config-hashes.txt; }; then
    replace_config "$legacy" "$xdg"
    CONFIG_PATH="$xdg"
    CONFIG_DETAIL="$(pretty_path "$xdg") · the repo's, in place of the inlay.toml of Inlay 0.2"
    note "The inlay.toml of Inlay 0.2 is kept as $(pretty_path "$CONFIG_BACKUP")"
    return 0
  fi
  # Not something that the parser of Inlay can check
  CONFIG_PATH=""
  CONFIG_LEGACY=true
  CONFIG_LEGACY_PATH="$legacy"
  CONFIG_NEW_PATH="$xdg"
  CONFIG_REPLACEABLE=true
  CONFIG_STATE=warn
  CONFIG_DETAIL="$(pretty_path "$legacy") · Inlay 0.2, not read"
  warn "$(pretty_path "$legacy") is the config of Inlay 0.2, which Inlay $REPO_VERSION doesn't read: the config is Lua now,"
  warn "with camelCase keys. Inlay uses its built-in config until $(pretty_path "$xdg") exists. Write it there,"
  if [ "$CAN_ASK" = true ]; then
    warn "starting from the inlay.lua of the repo, which the question below can put there (yours is kept as a backup)."
  else
    warn "starting from the inlay.lua of the repo:  ./install.sh --reset-config  (yours is kept as a backup)."
  fi
}

# config_create <config folder> <config file>. There is no config yet
config_create() {
  local dir="$1" xdg="$2"
  # Remembered: a folder that this run has just created is not worth a backup when it gives way to a link
  if [ ! -d "$dir" ]; then CONFIG_CREATED=true; fi
  mkdir -p "$dir"
  CONFIG_REPLACEABLE=false
  cp inlay.lua "$xdg"
  CONFIG_DETAIL="$(pretty_path "$xdg") · new, a copy of the repo's"
}

# check_link_target <config folder> <folder> <link now: a folder, or empty> <a folder without inlay.lua: ask, copy
# or no>. Whether the config folder can be linked to <folder>, saying why not right below the question. Returns 0 if
# it can, 1 if it can't and 2 if it already is. A folder without inlay.lua gets the one of the repo: if the user
# says so (ask), or without asking (copy: the user picked it in a list that said so)
check_link_target() {
  local dir="$1" target="$2" current="$3" missing_config="$4" pretty
  pretty="$(pretty_path "$target")"
  if [ -f "$target" ]; then
    say_problem "$pretty is a file. The link is to the folder that holds your inlay.lua: $(pretty_path "$(dirname "$target")")"
    return 1
  fi
  if [ ! -d "$target" ]; then
    say_problem "$pretty is not an existing folder."
    return 1
  fi
  if [ -d "$dir" ] && [ "$target" -ef "$dir" ]; then
    if [ -n "$current" ]; then return 2; fi
    say_problem "$pretty is the config folder itself: it can't be a link to itself."
    return 1
  fi
  path_exists "$target/inlay.lua" && return 0
  if [ "$missing_config" = copy ] || { [ "$missing_config" = ask ] && checklist_ask_yes_no "$pretty has no inlay.lua. Copy the repo's into it?" y; }; then
    cp inlay.lua "$target/inlay.lua"
    note "Copied the inlay.lua of the repo to $pretty/inlay.lua"
    return 0
  fi
  if [ "$missing_config" = no ]; then
    warn "$pretty has no inlay.lua, and there is no terminal to ask about copying one: nothing was linked."
  fi
  return 1
}

# link_config_dir <config folder> <folder> <link now, or empty>. Makes the config folder a symbolic link to the folder.
# A real config folder is never deleted: it is renamed. A previous link is only replaced
link_config_dir() {
  local dir="$1" target="$2" current="$3" backup
  if [ -n "$current" ]; then
    rm "$dir"
    note "The previous link, to $(pretty_path "$current"), was removed. That folder wasn't touched."
  elif [ -d "$dir" ]; then
    # The copy that this run has just made, alone in a folder that this run has just made: nothing to keep
    if [ "$CONFIG_CREATED" = true ] && rm -f "$dir/inlay.lua" && rmdir "$dir" 2>/dev/null; then
      :
    else
      backup="$(backup_path "$dir")"
      mv "$dir" "$backup"
      note "Your previous $(pretty_path "$dir") wasn't deleted: it is now $(pretty_path "$backup")"
    fi
  fi
  ln -s "$target" "$dir"
  CONFIG_PATH="$dir/inlay.lua"
  CONFIG_CREATED=false
  CONFIG_STATE=ok
  CONFIG_REPLACEABLE=false
  CONFIG_LEGACY=false
  config_kept "$CONFIG_PATH" "$(pretty_path "$dir") → $(pretty_path "$target")"
}

# config_place <config folder> <link: a folder, or empty> <prompt: true|false>. Where the config lives: the folder of
# --config-link, or the answer to the question, which is asked on every run. See "Your own config folder"
config_place() {
  local dir="$1" link="$2" prompt="$3" current="" legacy file suggestion="" found candidate target status hint extra
  local options actions action
  if [ -L "$dir" ]; then current="$(readlink "$dir")"; fi

  if [ -n "$link" ]; then
    target="$(absolute_path "$link" "$START_DIR")"
    # Without the trailing slashes: the link is to the folder
    while [ "$target" != / ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done
    status=0
    check_link_target "$dir" "$target" "$current" "$([ "$CAN_ASK" = true ] && echo ask || echo no)" || status=$?
    case "$status" in
      0) link_config_dir "$dir" "$target" "$current" ;;
      1) warn "--config-link $(pretty_path "$target"): nothing was linked." ;;
    esac
    return 0
  fi
  [ "$prompt" = true ] && [ "$CAN_ASK" = true ] || return 0

  # A previous version linked the file instead: the folder that holds it is the obvious one to link
  for file in inlay.lua inlay.toml; do
    if [ -z "$current" ] && [ -z "$suggestion" ] && [ -L "$dir/$file" ]; then
      legacy="$(readlink "$dir/$file")"
      if [ "$(basename "$legacy")" = "$file" ]; then suggestion="$(dirname "$(absolute_path "$legacy" "$dir")")"; fi
    fi
  done
  found="$(link_candidates "$dir" "$suggestion")"
  while true; do
    options=()
    actions=()
    if [ -n "$current" ]; then
      options[${#options[@]}]="Keep the link${TAB}${CONFIG_DETAIL#* · }"
    else
      options[${#options[@]}]="Keep it${TAB}${CONFIG_DETAIL#* · }"
    fi
    actions[${#actions[@]}]=keep
    if [ "$CONFIG_LEGACY" = true ]; then
      options[${#options[@]}]="Use the repo's inlay.lua${TAB}your inlay.toml is kept as a backup"
      actions[${#actions[@]}]=repo
    elif [ "$CONFIG_DIFFERS" = true ] && [ "$CONFIG_REPLACEABLE" = true ]; then
      options[${#options[@]}]="Use the repo's inlay.lua${TAB}yours is kept as a backup"
      actions[${#actions[@]}]=repo
    fi
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if path_exists "$candidate/inlay.lua"; then
        options[${#options[@]}]="Use $(pretty_path "$candidate")${TAB}has inlay.lua"
      elif path_exists "$candidate/inlay.toml"; then
        options[${#options[@]}]="Use $(pretty_path "$candidate")${TAB}has an inlay.toml of 0.2: gets the repo's inlay.lua"
      else
        options[${#options[@]}]="Use $(pretty_path "$candidate")${TAB}gets a copy of the repo's inlay.lua"
      fi
      actions[${#actions[@]}]="link$TAB$candidate"
    done <<LIST
$found
LIST
    options[${#options[@]}]="Another folder...${TAB}type its path"
    actions[${#actions[@]}]=another
    hint="↑↓ · Enter"
    extra=""
    if [ "$CONFIG_DIFFERS" = true ]; then
      hint="$hint · d shows the diff with the repo's"
      extra=d
    fi

    CL_MENU_STEP="$S_CONFIG"
    checklist_set "$S_CONFIG" ask "$CONFIG_DETAIL"
    if [ "$CL_ACTIVE" != true ]; then printf '    Where should your config live? It is %s\n' "$CONFIG_DETAIL"; fi
    checklist_menu "$hint" "$extra" "${options[@]}"
    if [ "$CHOICE" -eq 0 ]; then
      show_in_pager show_config_differences "$CONFIG_PATH"
      checklist_draw
      continue
    fi
    action="${actions[$((CHOICE - 1))]}"
    case "$action" in
      keep) return 0 ;;
      repo)
        if [ "$CONFIG_LEGACY" = true ]; then
          replace_config "$CONFIG_LEGACY_PATH" "$CONFIG_NEW_PATH"
          CONFIG_PATH="$CONFIG_NEW_PATH"
        else
          replace_config "$CONFIG_PATH"
        fi
        CONFIG_DETAIL="$(pretty_path "$CONFIG_PATH") · the repo's inlay.lua"
        CONFIG_STATE=ok
        CONFIG_DIFFERS=false
        CONFIG_LEGACY=false
        CONFIG_REPLACEABLE=false
        note "Your previous config is kept as $(pretty_path "$CONFIG_BACKUP")"
        return 0
        ;;
      link*)
        target="${action#*"$TAB"}"
        status=0
        check_link_target "$dir" "$target" "$current" copy || status=$?
        case "$status" in
          0) link_config_dir "$dir" "$target" "$current"; return 0 ;;
          2) return 0 ;;
        esac
        ;;
      another)
        # Without the options: the question takes their place
        checklist_draw
        while true; do
          checklist_ask_path "Folder"
          [ -n "$ANSWER" ] || break
          target="$(absolute_path "$ANSWER" "$START_DIR")"
          # Without the trailing slashes: the link is to the folder. Tab leaves one after the name of a folder
          while [ "$target" != / ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done
          status=0
          check_link_target "$dir" "$target" "$current" ask || status=$?
          case "$status" in
            0) link_config_dir "$dir" "$target" "$current"; return 0 ;;
            2) return 0 ;;
          esac
          # A folder of the list with the name that was typed is most likely what was meant
          candidate="$(printf '%s' "$found" | grep -m 1 "/$(basename "$target")\$" || true)"
          if [ -n "$candidate" ] && [ "$candidate" != "$target" ]; then say_hint "Did you mean $(pretty_path "$candidate")?"; fi
        done
        ;;
    esac
    checklist_draw
  done
}

# Says what the parser of the app that was just installed thinks of the config. Never fails the installation.
# Sets CONFIG_CHECK: ok, warnings, errors, or nothing when there is nothing to check
check_config() {
  local binary="$INSTALL_TARGET/Contents/MacOS/$APP_NAME" output status=0 line
  CONFIG_CHECK=""
  [ -n "$CONFIG_PATH" ] && [ -x "$binary" ] && [ -e "$CONFIG_PATH" ] || return 0
  output="$("$binary" --check-config "$CONFIG_PATH" 2>&1)" || status=$?
  case "$output" in
    *"has no errors or warnings") CONFIG_CHECK=ok ;;
    *)
      CONFIG_CHECK=warnings
      CONFIG_STATE=warn
      CONFIG_DETAIL="$CONFIG_DETAIL · warnings"
      printf '%s\n' "$output" | while IFS= read -r line; do warn "$line"; done
      ;;
  esac
  if [ "$status" -ne 0 ]; then
    CONFIG_CHECK=errors
    CONFIG_STATE=warn
    CONFIG_DETAIL="${CONFIG_DETAIL% · warnings} · errors"
    warn "The config has errors. Inlay starts anyway and shows them in a window. Fix them and save the file."
  fi
}

# config_step <link: a folder, or empty> <prompt: true|false> <reset: true|false>
# Creates the config when there is none, says what happens to the one that is there, and asks where it should live.
# See "Your config". Sets CONFIG_PATH to the config that Inlay will read, or to nothing if it can't tell (two configs,
# or an inlay.toml of Inlay 0.2 that isn't read)
config_step() {
  local link="$1" prompt="$2" reset="$3" dir xdg dotfile
  dir="$(config_home)/inlay"
  xdg="$dir/inlay.lua"
  dotfile="$HOME/.inlay.lua"
  CONFIG_PATH=""
  CONFIG_CREATED=false
  CONFIG_STATE=ok
  CONFIG_DIFFERS=false
  CONFIG_LEGACY=false
  checklist_set "$S_CONFIG" run

  if path_exists "$dotfile"; then
    if path_exists "$xdg"; then
      CONFIG_STATE=warn
      CONFIG_DETAIL="$(pretty_path "$dotfile") and $(pretty_path "$xdg") · two configs"
      warn "Inlay reports an ambiguous config until you remove one of them."
      if [ "$reset" = true ]; then warn "--reset-config was ignored: it can't tell which of the two is your config."; fi
    else
      CONFIG_PATH="$dotfile"
      config_file "$dotfile" "$reset"
    fi
    # Inlay reads either file, never both: a linked folder next to ~/.inlay.lua would be a second config
    if [ -n "$link" ]; then
      warn "--config-link was ignored: your config is ~/.inlay.lua. To use a config folder, move that file into the"
      warn "folder as inlay.lua and run this script again."
    fi
  else
    if [ -L "$dir" ]; then
      CONFIG_PATH="$xdg"
      config_linked_folder "$dir" "$reset"
    elif path_exists "$xdg"; then
      CONFIG_PATH="$xdg"
      config_file "$xdg" "$reset"
    elif path_exists "$dir/inlay.toml"; then
      config_legacy "$dir/inlay.toml" "$xdg" "$reset"
    elif path_exists "$HOME/.inlay.toml"; then
      config_legacy "$HOME/.inlay.toml" "$dotfile" "$reset"
    else
      CONFIG_PATH="$xdg"
      if [ "$reset" = true ]; then note "--reset-config: you had no Inlay config to replace."; fi
      config_create "$dir" "$xdg"
    fi
    config_place "$dir" "$link" "$prompt"
  fi
  if [ "${XDG_CONFIG_HOME:-$HOME/.config}" != "$HOME/.config" ]; then
    note "XDG_CONFIG_HOME is set in this shell. Inlay only finds the config there if it is also set for the apps that"
    note "macOS starts (launchctl setenv). Otherwise it reads ~/.config/inlay/inlay.lua."
  fi
  check_config
  checklist_set "$S_CONFIG" "$CONFIG_STATE" "$CONFIG_DETAIL"
}

# Opens Inlay, or says why not. Sets OPEN_STATUS: open, conflict, failed or no-open
open_or_explain() {
  local open_app="$1"
  checklist_set "$S_OPEN" run
  find_conflicts
  if [ -n "$CONFLICTS" ]; then
    OPEN_STATUS=conflict
    checklist_set "$S_OPEN" warn "not opened: $CONFLICTS running"
    warn "These apps do the same job as Inlay: $CONFLICTS. Two window managers at once fight over your windows,"
    warn "so Inlay was not opened, and this script doesn't quit other apps for you. Quit them (AeroSpace and AeroMenu"
    warn "from their menu bar icons; borders with 'brew services stop borders'), then:  open \"$INSTALL_TARGET\""
  elif [ "$open_app" = true ]; then
    if open "$INSTALL_TARGET"; then
      OPEN_STATUS=open
      checklist_set "$S_OPEN" ok "running in the menu bar"
    else
      OPEN_STATUS=failed
      checklist_set "$S_OPEN" warn "could not open it"
      warn "Open it by hand:  open \"$INSTALL_TARGET\""
    fi
  else
    OPEN_STATUS=no-open
    checklist_set "$S_OPEN" ok "not opened (--no-open)"
  fi
}

# The last lines: how long it took, and the one thing to do the first time
finish() {
  echo
  if [ -n "$C_RESET" ]; then
    printf '  %s✓%s %s%s %s is installed%s  %s%s · %s uninstall removes it%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$APP_NAME" \
      "$REPO_VERSION" "$C_RESET" "$C_DIM" "$(format_duration $((SECONDS - START_SECONDS)))" "$CLI_NAME" "$C_RESET"
  else
    success "$APP_NAME $REPO_VERSION is installed" "($(format_duration $((SECONDS - START_SECONDS))))"
  fi
  if [ "$OPEN_STATUS" = open ]; then
    hint "The first time: allow $APP_NAME in System Settings > Privacy & Security > Accessibility."
  fi
  if [ "$SIGNED_WITH" = adhoc ]; then
    hint "After every rebuild: remove it from that list (-) and allow it again (ad hoc signature)."
  fi
}

main() {
  local open_app=true signing=stable config_link="" prompt=true reset_config=false assume_yes=false
  VERBOSE=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-open) open_app=false ;;
      --stable-signing) signing=stable ;;
      --adhoc-signing) signing=adhoc ;;
      --import-aerospace) fail "--import-aerospace is gone: the config of Inlay is Lua since 0.3.0, and an aerospace.toml can't be read." ;;
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
  checklist_groups "$S_REQUIREMENTS:Prepare" "$S_INSTALL:Install" "$S_CONFIG:Configure"
  checklist_start Requirements Build App CLI Config "Open $APP_NAME"
  checklist_set "$S_REQUIREMENTS" run
  if ! check_requirements; then
    checklist_set "$S_REQUIREMENTS" bad "$REQ_PROBLEMS to fix"
    checklist_end
    explain_requirements
  fi
  checklist_set "$S_REQUIREMENTS" ok "macOS $REQ_MACOS · Swift $SWIFT_VERSION · codesign"
  choose_install_dir
  plan "$signing" "$reset_config" "$open_app"
  if [ "$CAN_ASK" = true ] && [ "$assume_yes" != true ]; then
    if ! checklist_confirm install; then
      checklist_end
      printf '\n  Nothing was done.\n'
      exit 1
    fi
    checklist_draw
  fi

  start_log
  build_app "$signing"
  install_app
  link_cli
  config_step "$config_link" "$prompt" "$reset_config"
  open_or_explain "$open_app"
  checklist_end
  finish
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
