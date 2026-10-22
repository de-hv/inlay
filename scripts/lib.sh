#!/usr/bin/env bash
# Helpers shared by the scripts in this directory. Meant to be sourced, not run.
# Compatible with the bash 3.2 that ships with macOS.

APP_NAME="Inlay"
CLI_NAME="inlay"
BUNDLE_ID="com.davidhiguita.inlay"
CLT_DIR="/Library/Developer/CommandLineTools"
# Where the CLI lives inside the bundle. It can't sit next to Contents/MacOS/Inlay: on a case-insensitive file
# system 'inlay' and 'Inlay' are the same file
CLI_PATH_IN_APP="Contents/Resources/bin/$CLI_NAME"

# Local self-signed identity that 'install.sh' creates and signs with
SIGN_IDENTITY_NAME="${INLAY_SIGN_IDENTITY_NAME:-Inlay Local Code Signing}"
# Keychain that holds it. Empty means the login keychain
SIGN_KEYCHAIN="${INLAY_SIGN_KEYCHAIN:-}"

# Colors and symbols only go to a terminal that shows them: not to a pipe or a log, and not with NO_COLOR
# (https://no-color.org) or TERM=dumb. Without them the output is the plain one: '==>', 'warning:', 'error:'
use_color() { [ -t "$1" ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }
# set_styles <prefix> <file descriptor>: <prefix>_BOLD, <prefix>_DIM... are escape sequences, or empty
set_styles() {
  local bold="" dim="" red="" green="" yellow="" blue="" cyan="" magenta="" reset=""
  if use_color "$2"; then
    bold=$'\033[1m' dim=$'\033[2m' red=$'\033[31m' green=$'\033[32m' yellow=$'\033[33m'
    blue=$'\033[34m' cyan=$'\033[36m' magenta=$'\033[35m' reset=$'\033[0m'
  fi
  eval "${1}_BOLD=\$bold ${1}_DIM=\$dim ${1}_RED=\$red ${1}_GREEN=\$green ${1}_YELLOW=\$yellow"
  eval "${1}_BLUE=\$blue ${1}_CYAN=\$cyan ${1}_MAGENTA=\$magenta ${1}_RESET=\$reset"
}
set_styles C 1 # Standard output
set_styles E 2 # Standard error: the warnings and the errors

# A step of the script: '==> Requirements' and, dimmed, its details
info() {
  if [ $# -gt 1 ]; then
    printf '%s==>%s %s%s%s  %s%s%s\n' "$C_BOLD$C_BLUE" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "$C_DIM" "$2" "$C_RESET"
  else
    printf '%s==>%s %s%s%s\n' "$C_BOLD$C_BLUE" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
  fi
}
# Something done: '  ✓ Installed …'
ok() {
  if [ -n "$C_RESET" ]; then printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; else printf '==> %s\n' "$*"; fi
}
note() { printf '    %s\n' "$*"; }
# An explanation that can be skimmed
hint() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
warn() {
  if [ -n "$E_RESET" ]; then printf '  %s!%s %s\n' "$E_YELLOW" "$E_RESET" "$*" >&2; else printf 'warning: %s\n' "$*" >&2; fi
}
# Something the user can fix right away, like a path typed wrong. The script goes on
problem() {
  if [ -n "$E_RESET" ]; then printf '  %s✗%s %s\n' "$E_RED" "$E_RESET" "$*" >&2; else printf 'warning: %s\n' "$*" >&2; fi
}
fail() {
  if [ -n "$E_RESET" ]; then printf '  %s✗ error:%s %s\n' "$E_BOLD$E_RED" "$E_RESET" "$*" >&2; else printf 'error: %s\n' "$*" >&2; fi
  exit 1
}
# The last line of a script that went well
success() { printf '%s==>%s %s%s%s%s\n' "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "${2:+ $2}"; }

# ~/.config/inlay instead of /Users/me/.config/inlay: shorter, and what people type
pretty_path() {
  case "$1" in
    "$HOME") printf '~\n' ;;
    "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Inlay must build without Xcode, so every script uses the Command Line Tools even when xcode-select points to
# an Xcode.app. Set INLAY_USE_SELECTED_TOOLCHAIN=1 to build with whatever toolchain is selected instead.
use_command_line_tools() {
  if [ "${INLAY_USE_SELECTED_TOOLCHAIN:-0}" = 1 ]; then
    command -v swift >/dev/null 2>&1 || fail "swift was not found in the selected toolchain."
    return 0
  fi
  if [ ! -x "$CLT_DIR/usr/bin/swift" ]; then
    printf 'error: the Xcode Command Line Tools are not installed (%s is missing).\n' "$CLT_DIR" >&2
    printf '       Install them with:  xcode-select --install\n' >&2
    printf '       and run this script again. Xcode itself is not needed.\n' >&2
    exit 1
  fi
  export DEVELOPER_DIR="$CLT_DIR"
}

# Prints "major.minor" of the active Swift compiler
swift_version() {
  swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1
}

# version_at_least <actual major.minor> <wanted major> <wanted minor>
version_at_least() {
  local major="${1%%.*}" minor="${1#*.}"
  minor="${minor%%.*}"
  [ "$major" -gt "$2" ] || { [ "$major" -eq "$2" ] && [ "$minor" -ge "$3" ]; }
}

sign_keychain_path() {
  if [ -n "$SIGN_KEYCHAIN" ]; then
    printf '%s\n' "$SIGN_KEYCHAIN"
  else
    printf '%s\n' "$HOME/Library/Keychains/login.keychain-db"
  fi
}

has_signing_identity() {
  local identities
  identities="$(security find-identity -p codesigning "$(sign_keychain_path)" 2>/dev/null || true)"
  case "$identities" in
    *"\"$SIGN_IDENTITY_NAME\""*) return 0 ;;
    *) return 1 ;;
  esac
}

# Creates the self-signed code signing identity unless it already exists. Returns non-zero when it can't.
#
# The certificate is not trusted by the system, and it doesn't need to be: macOS only uses it to tell that two
# builds of Inlay come from the same place, so the Accessibility permission survives a rebuild. The private key
# never leaves this Mac: it is generated in a temporary directory, imported into the keychain and deleted.
ensure_signing_identity() {
  local keychain work pass status=0
  keychain="$(sign_keychain_path)"
  if has_signing_identity; then
    return 0
  fi
  [ -f "$keychain" ] || { warn "keychain $keychain was not found."; return 1; }
  [ -x /usr/bin/openssl ] || { warn "/usr/bin/openssl was not found."; return 1; }

  work="$(mktemp -d)" || return 1
  pass="$(/usr/bin/openssl rand -hex 16)" || { rm -rf "$work"; return 1; }
  (
    umask 077
    cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_IDENTITY_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
      -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1 &&
      /usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
        -name "$SIGN_IDENTITY_NAME" -out "$work/identity.p12" -passout "pass:$pass" >/dev/null 2>&1 &&
      security import "$work/identity.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign >/dev/null
  ) || status=1
  rm -rf "$work"
  if [ "$status" -ne 0 ] || ! has_signing_identity; then
    warn "could not create the signing identity."
    return 1
  fi
  ok "Created the self-signed signing identity \"$SIGN_IDENTITY_NAME\""
  hint "It lives in $(pretty_path "$keychain"). To remove it, delete it in Keychain Access."
  return 0
}

# INLAY_LSREGISTER and INLAY_TMP_DIR exist so that the scripts can be tried without touching the Launch Services
# database or the files of a running Inlay
LSREGISTER="${INLAY_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
# Where Inlay keeps its runtime files (/tmp/com.davidhiguita.inlay)
RUNTIME_TMP_DIR="${INLAY_TMP_DIR:-/tmp}"

inlay_is_running() { pgrep -x "$APP_NAME" >/dev/null 2>&1; }

# Quits a running Inlay and waits for it. Inlay restores the hidden windows when it gets SIGTERM.
quit_running_inlay() {
  local i=0
  inlay_is_running || return 0
  pkill -x "$APP_NAME" 2>/dev/null || true
  while inlay_is_running; do
    i=$((i + 1))
    if [ "$i" -gt 100 ]; then
      fail "$APP_NAME is still running. Quit it from its menu bar icon and run this script again."
    fi
    sleep 0.1
  done
  ok "Quit the running $APP_NAME ${C_DIM}· the windows of the hidden workspaces are back on screen${C_RESET}"
}

# Prints the version of an Inlay.app (CFBundleShortVersionString), or nothing
app_version() {
  plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
}

# Directories where the 'inlay' CLI may be linked, best first
cli_dir_candidates() {
  printf '%s\n' "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin
}

dir_is_in_path() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

config_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

# Prints the SHA-256 of the standard input, in hexadecimal
sha256_of_stdin() { /usr/bin/shasum -a 256 | cut -d ' ' -f 1; }

# is_known_default_config <config file> <list of hashes>. The file is identical to a default config that Inlay
# has shipped: nobody has edited it. See: scripts/update-default-config-hashes.sh
is_known_default_config() {
  local hash
  [ -f "$1" ] && [ -f "$2" ] || return 1
  hash="$(sha256_of_stdin < "$1")" || return 1
  [ -n "$hash" ] && grep -q "^$hash  " "$2"
}

# Somebody is at the keyboard to answer a question
is_interactive() { [ -t 0 ]; }

# ask_yes_no <question> [<default: n|y>]. Asks on the terminal. Enter gives the default, which is no unless
# told otherwise; any other answer than a yes is a no
ask_yes_no() {
  local answer="" default="${2:-n}" choices="[y/N]"
  if [ "$default" = y ]; then choices="[Y/n]"; fi
  if [ -n "$C_RESET" ]; then
    printf '  %s?%s %s%s%s %s%s%s ' "$C_CYAN" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "$C_DIM" "$choices" "$C_RESET"
  else
    printf '    %s %s ' "$1" "$choices"
  fi
  IFS= read -r answer || answer=""
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    "") [ "$default" = y ] ;;
    *) return 1 ;;
  esac
}

# ask_path <label> <help>. Asks for a path on the terminal, with the line editing of readline: Tab completes the
# names of files and folders. Sets ANSWER to what was typed, without the spaces around it
ask_path() {
  local prompt start="" end=""
  if [ -n "$C_RESET" ]; then
    # Readline must not count the escape sequences as characters of the prompt: they go between \001 and \002
    start=$'\001' end=$'\002'
    prompt="  $start$C_CYAN$end?$start$C_RESET$C_BOLD$end $1$start$C_RESET$C_DIM$end ($2):$start$C_RESET$end "
  else
    prompt="    $1 ($2): "
  fi
  ANSWER=""
  IFS= read -r -e -p "$prompt" ANSWER || ANSWER=""
  ANSWER="$(printf '%s' "$ANSWER" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
}

# absolute_path <path> [<base directory>]. Expands a leading ~ and makes the path absolute. Prints it
absolute_path() {
  local path="$1" base="${2:-$PWD}"
  case "$path" in
    "~") path="$HOME" ;;
    "~/"*) path="$HOME/${path#"~/"}" ;;
  esac
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$base/$path" ;;
  esac
}

# ~~~ The interactive parts: steps, a spinner, menus ~~~

TAB=$'\t'
ESC=$'\033'

# Menus need somebody at the keyboard and a terminal that shows colors: they redraw themselves. Elsewhere the
# scripts ask and print line by line
fancy_ui() { [ -n "$C_RESET" ] && [ -t 0 ] && [ -t 1 ]; }

term_width() {
  local width
  width="$(tput cols 2>/dev/null || true)"
  case "$width" in ''|*[!0-9]*) width="${COLUMNS:-80}" ;; esac
  printf '%s\n' "$width"
}

# format_duration <seconds>: '48s', '2m 14s'
format_duration() {
  if [ "$1" -ge 60 ]; then printf '%dm %02ds\n' $(($1 / 60)) $(($1 % 60)); else printf '%ds\n' "$1"; fi
}

STEP=0
STEP_TOTAL=0
# step <label> [<detail>]. The heading of a step of the script: '[2/5] Install'
step() {
  STEP=$((STEP + 1))
  echo
  if [ -n "$C_RESET" ]; then
    printf '%s[%d/%d]%s %s%s%s%s\n' "$C_BOLD$C_BLUE" "$STEP" "$STEP_TOTAL" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" \
      "${2:+  $C_DIM$2$C_RESET}"
  else
    printf '==> [%d/%d] %s%s\n' "$STEP" "$STEP_TOTAL" "$1" "${2:+  $2}"
  fi
}

# requirement_row <ok|bad|warn> <what> [<detail>]. A line of a list of requirements
requirement_row() {
  local mark
  if [ -n "$C_RESET" ]; then
    case "$1" in
      ok) mark="${C_GREEN}✓$C_RESET" ;;
      bad) mark="${C_RED}✗$C_RESET" ;;
      *) mark="$C_YELLOW!$C_RESET" ;;
    esac
    printf '  %s %-24s %s\n' "$mark" "$2" "${3:-}"
  else
    case "$1" in
      ok) mark="ok  " ;;
      bad) mark="FAIL" ;;
      *) mark="warn" ;;
    esac
    printf '    %s  %-24s %s\n' "$mark" "$2" "${3:-}"
  fi
}

# command_box <command>. A command to copy, or to run: in a box
command_box() {
  local rule
  if [ -z "$C_RESET" ]; then
    printf '        %s\n' "$1"
    return 0
  fi
  rule="$(printf '%*s' $((${#1} + 4)) '' | sed 's/ /─/g')"
  printf '  %s┌%s┐%s\n' "$C_DIM" "$rule" "$C_RESET"
  printf '  %s│%s  %s%s%s  %s│%s\n' "$C_DIM" "$C_RESET" "$C_BOLD$C_GREEN" "$1" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '  %s└%s┘%s\n' "$C_DIM" "$rule" "$C_RESET"
}

# Kills a process and the processes that it started (a background job doesn't get the Ctrl-C of the terminal)
kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null || true); do kill_tree "$child"; done
  kill "$1" 2>/dev/null || true
}

# spin_command <log> <command>... Runs the command with its output in the log. On a terminal that shows colors,
# one line redrawn in place says how far it got: the '[n/m]' of swift build, or the last '==>' line. Elsewhere, and
# with VERBOSE=true, the output is shown as it comes, and it also goes to the log. Returns the status of the
# command, and sets SPIN_SECONDS to how long it took
spin_command() {
  local log="$1" pid status=0 start="$SECONDS" frame=0 line text count total filled bar i width elapsed
  local frames="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏" spinner
  shift
  if [ "${VERBOSE:-false}" = true ] || [ -z "$C_RESET" ]; then
    "$@" 2>&1 | tee -a "$log" || status=$?
    SPIN_SECONDS=$((SECONDS - start))
    return "$status"
  fi
  "$@" >>"$log" 2>&1 &
  pid=$!
  width="$(term_width)"
  printf '\033[?25l'
  trap 'kill_tree "$pid"; printf "\r\033[2K\033[?25h"; exit 130' INT
  # shellcheck disable=SC2086
  set -- $frames
  while kill -0 "$pid" 2>/dev/null; do
    line="$(grep -E '^(\[[0-9]+/[0-9]+\] |==> )' "$log" 2>/dev/null | tail -n 1 || true)"
    elapsed="$(format_duration $((SECONDS - start)))"
    eval "spinner=\${$((frame + 1))}"
    case "$line" in
      "["*)
        count="${line#[}" && count="${count%%/*}"
        total="${line#*/}" && total="${total%%]*}"
        text="${line#*] }" && text="${text##* }"
        [ "$total" -gt 0 ] 2>/dev/null || total=1
        filled=$((count * 24 / total))
        bar="$C_CYAN"
        i=0
        while [ "$i" -lt 24 ]; do
          if [ "$i" -eq "$filled" ]; then bar="$bar$C_RESET$C_DIM"; fi
          bar="${bar}━"
          i=$((i + 1))
        done
        printf '\r\033[2K  %s%s%s %-28.28s %s%s %s%s%s%s/%s  %s%s' "$C_CYAN" "$spinner" "$C_RESET" "$text" "$bar" \
          "$C_RESET" "$C_BOLD" "$count" "$C_RESET" "$C_DIM" "$total" "$elapsed" "$C_RESET"
        ;;
      *)
        text="${line#==> }"
        case "$text" in
          "Signing with"*) text="Signing · if macOS asks for your keychain password, choose \"Always Allow\"" ;;
          "") text="Starting" ;;
        esac
        printf '\r\033[2K  %s%s%s %s  %s%s%s' "$C_CYAN" "$spinner" "$C_RESET" "${text:0:$((width - 16))}" "$C_DIM" \
          "$elapsed" "$C_RESET"
        ;;
    esac
    frame=$(((frame + 1) % 10))
    sleep 0.15
  done
  wait "$pid" || status=$?
  printf '\r\033[2K\033[?25h'
  trap - INT
  SPIN_SECONDS=$((SECONDS - start))
  return "$status"
}

# split_option "<label><TAB><detail>": sets OPT_LABEL and OPT_DETAIL
split_option() {
  OPT_LABEL="${1%%"$TAB"*}"
  OPT_DETAIL=""
  case "$1" in *"$TAB"*) OPT_DETAIL="${1#*"$TAB"}" ;; esac
}

# The width of the longest label of the options
label_width() {
  local option width=0
  for option in "$@"; do
    split_option "$option"
    if [ "${#OPT_LABEL}" -gt "$width" ]; then width="${#OPT_LABEL}"; fi
  done
  printf '%s\n' "$width"
}

# read_key: reads one key press into KEY: up, down, space, enter, or the character
read_key() {
  local key="" rest=""
  IFS= read -rsn1 key || { KEY=enter; return 0; }
  case "$key" in
    "$ESC")
      IFS= read -rsn2 -t 1 rest || true
      case "$rest" in
        "[A"|OA) KEY=up ;;
        "[B"|OB) KEY=down ;;
        *) KEY=escape ;;
      esac
      ;;
    "") KEY=enter ;;
    " ") KEY=space ;;
    *) KEY="$key" ;;
  esac
}

# choose_one <question> <hint> <option>... One option out of a list: with the arrows and Enter on a terminal that
# shows colors, by its number elsewhere. An option is "<label><TAB><detail>". Enter alone picks the first one.
# Sets CHOICE to the number of the option, from 1
choose_one() {
  local question="$1" hint="$2" count selected=1 width option i answer
  shift 2
  count=$#
  width="$(label_width "$@")"

  if ! fancy_ui; then
    printf '    %s\n' "$question"
    i=0
    for option in "$@"; do
      i=$((i + 1))
      split_option "$option"
      printf '     %2d) %-*s  %s\n' "$i" "$width" "$OPT_LABEL" "$OPT_DETAIL"
    done
    while true; do
      printf '    Choice [1]: '
      IFS= read -r answer || answer=""
      case "$answer" in
        "") CHOICE=1; return 0 ;;
        *[!0-9]*) ;;
        *) if [ "$answer" -ge 1 ] && [ "$answer" -le "$count" ]; then CHOICE="$answer"; return 0; fi ;;
      esac
    done
  fi

  printf '  %s?%s %s%s%s  %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$question" "$C_RESET" "$C_DIM" "$hint" "$C_RESET"
  printf '\033[?25l'
  trap 'printf "\033[?25h\n"; exit 130' INT
  while true; do
    i=0
    for option in "$@"; do
      i=$((i + 1))
      split_option "$option"
      if [ "$i" -eq "$selected" ]; then
        printf '\033[2K    %s❯ %s%-*s%s  %s%s%s\n' "$C_CYAN" "$C_BOLD" "$width" "$OPT_LABEL" "$C_RESET" "$C_DIM" "$OPT_DETAIL" "$C_RESET"
      else
        printf '\033[2K      %-*s  %s%s%s\n' "$width" "$OPT_LABEL" "$C_DIM" "$OPT_DETAIL" "$C_RESET"
      fi
    done
    read_key
    case "$KEY" in
      up|k) if [ "$selected" -gt 1 ]; then selected=$((selected - 1)); else selected="$count"; fi ;;
      down|j) if [ "$selected" -lt "$count" ]; then selected=$((selected + 1)); else selected=1; fi ;;
      [1-9]) if [ "$KEY" -le "$count" ]; then selected="$KEY"; fi ;;
      enter) break ;;
    esac
    printf '\033[%dA' "$count"
  done
  # The list gives way to the answer
  printf '\033[%dA\033[J' "$((count + 1))"
  eval "option=\${$selected}"
  split_option "$option"
  printf '  %s?%s %s%s%s %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$question" "$C_RESET" "$C_CYAN" "$OPT_LABEL" "$C_RESET"
  printf '\033[?25h'
  trap - INT
  CHOICE="$selected"
}

# choose_many <question> <hint> <option>... Checkboxes: Space checks and unchecks, 'a' all of them, Enter is done.
# Without a terminal that shows colors, one yes/no question per option. An option is "on<TAB><label><TAB><detail>"
# or "off<TAB>…": checked or not at first. Sets CHOSEN to the numbers of the checked ones, between spaces: " 1 3 "
choose_many() {
  local question="$1" hint="$2" count selected=1 width option i all states=""
  shift 2
  count=$#
  for option in "$@"; do
    case "$option" in on"$TAB"*) states="${states}1" ;; *) states="${states}0" ;; esac
  done
  width=0
  for option in "$@"; do
    split_option "${option#*"$TAB"}"
    if [ "${#OPT_LABEL}" -gt "$width" ]; then width="${#OPT_LABEL}"; fi
  done
  CHOSEN=" "
  if ! fancy_ui; then
    printf '    %s\n' "$question"
    i=0
    for option in "$@"; do
      i=$((i + 1))
      split_option "${option#*"$TAB"}"
      if ask_yes_no "$OPT_LABEL${OPT_DETAIL:+ ($OPT_DETAIL)}?" "$([ "${states:$((i - 1)):1}" = 1 ] && echo y || echo n)"; then
        CHOSEN="$CHOSEN$i "
      fi
    done
    return 0
  fi

  printf '  %s?%s %s%s%s  %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$question" "$C_RESET" "$C_DIM" "$hint" "$C_RESET"
  printf '\033[?25l'
  trap 'printf "\033[?25h\n"; exit 130' INT
  while true; do
    i=0
    for option in "$@"; do
      i=$((i + 1))
      split_option "${option#*"$TAB"}"
      if [ "$i" -eq "$selected" ]; then printf '\033[2K  %s❯%s ' "$C_CYAN" "$C_RESET"; else printf '\033[2K    '; fi
      if [ "${states:$((i - 1)):1}" = 1 ]; then printf '%s[x]%s ' "$C_GREEN" "$C_RESET"; else printf '%s[ ]%s ' "$C_DIM" "$C_RESET"; fi
      printf '%-*s  %s%s%s\n' "$width" "$OPT_LABEL" "$C_DIM" "$OPT_DETAIL" "$C_RESET"
    done
    [ "$selected" -gt 0 ] || break
    read_key
    case "$KEY" in
      up|k) if [ "$selected" -gt 1 ]; then selected=$((selected - 1)); else selected="$count"; fi ;;
      down|j) if [ "$selected" -lt "$count" ]; then selected=$((selected + 1)); else selected=1; fi ;;
      space|x)
        i=$((selected - 1))
        if [ "${states:$i:1}" = 1 ]; then all=0; else all=1; fi
        states="${states:0:$i}$all${states:$((i + 1))}"
        ;;
      a)
        case "$states" in *0*) all=1 ;; *) all=0 ;; esac
        states="$(printf '%*s' "$count" '' | tr ' ' "$all")"
        ;;
      enter) selected=0 ;;
    esac
    printf '\033[%dA' "$count"
  done
  printf '\033[?25h'
  trap - INT
  i=0
  while [ "$i" -lt "$count" ]; do
    if [ "${states:$i:1}" = 1 ]; then CHOSEN="$CHOSEN$((i + 1)) "; fi
    i=$((i + 1))
  done
}
