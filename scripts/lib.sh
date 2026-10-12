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

info() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

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
    info "Signing identity \"$SIGN_IDENTITY_NAME\" already exists"
    return 0
  fi
  [ -f "$keychain" ] || { warn "keychain $keychain was not found."; return 1; }
  [ -x /usr/bin/openssl ] || { warn "/usr/bin/openssl was not found."; return 1; }

  info "Creating the self-signed signing identity \"$SIGN_IDENTITY_NAME\""
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
  note "It lives in $keychain. To remove it, delete \"$SIGN_IDENTITY_NAME\" in Keychain Access."
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
  info "Quitting the running $APP_NAME"
  pkill -x "$APP_NAME" 2>/dev/null || true
  while inlay_is_running; do
    i=$((i + 1))
    if [ "$i" -gt 100 ]; then
      fail "$APP_NAME is still running. Quit it from its menu bar icon and run this script again."
    fi
    sleep 0.1
  done
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

# Somebody is at the keyboard to answer a question
is_interactive() { [ -t 0 ]; }

# ask_yes_no <question>. Asks on the terminal and returns 0 only for an explicit yes. The default is no
ask_yes_no() {
  local answer=""
  printf '%s [y/N] ' "$1"
  IFS= read -r answer || answer=""
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
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
