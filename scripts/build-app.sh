#!/usr/bin/env bash
#
# Builds Inlay.app (the window manager) and the 'inlay' CLI into ./build, using only the Xcode Command Line
# Tools: swift build + a hand-made bundle + codesign. No Xcode, no Apple ID.
#
#   scripts/build-app.sh                          release build, ad hoc signature
#   scripts/build-app.sh --sign-identity <name>   sign with a code signing identity from the keychain
#
# Result:
#   build/Inlay.app/Contents/MacOS/Inlay                         the app
#   build/Inlay.app/Contents/Resources/bin/inlay                 the CLI
#   build/Inlay.app/Contents/Resources/default-config.toml       the built-in config
#
# The version comes from the VERSION file and the git hash from the repo. Both are sealed into the binaries
# and into Info.plist.
#
# An ad hoc signature is enough to run on this Mac, but macOS identifies an ad hoc signed app by the hash of
# its code, so after every rebuild the Accessibility permission has to be granted again. A signature made with
# a stable identity (see 'scripts/install.sh --stable-signing') doesn't have that problem.

set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

usage() { sed -n '3,19s/^# \{0,1\}//p' "$0"; }

# Always a release build: a debug build calls itself Inlay-Debug and uses another bundle id and socket, so it
# doesn't fit this bundle. For debugging use 'swift build' and run .build/.../InlayApp directly
CONFIGURATION="release"
IDENTITY="${INLAY_SIGN_IDENTITY:--}"
while [ $# -gt 0 ]; do
  case "$1" in
    --sign-identity)
      [ $# -ge 2 ] || fail "--sign-identity needs a value."
      IDENTITY="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "unknown option: $1" ;;
  esac
done

use_command_line_tools

VERSION="$(tr -d '[:space:]' < VERSION)"
case "$VERSION" in
  ''|*[!0-9A-Za-z.-]*) fail "VERSION must only contain letters, digits, dots and dashes: '$VERSION'." ;;
esac

GIT_HASH="SNAPSHOT"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git rev-parse --verify --quiet HEAD >/dev/null; then
  GIT_HASH="$(git rev-parse HEAD)"
  if [ -n "$(git status --porcelain)" ]; then
    GIT_HASH="$GIT_HASH-dirty"
  fi
fi

# Package.swift reads these two and hands them to the BuildInfo target
export INLAY_VERSION="$VERSION"
export INLAY_GIT_HASH="$GIT_HASH"

info "Building $APP_NAME $VERSION ($GIT_HASH, $CONFIGURATION) with $(swift --version 2>&1 | head -n 1)"
swift build --configuration "$CONFIGURATION" --product InlayApp
swift build --configuration "$CONFIGURATION" --product "$CLI_NAME"
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
[ -x "$BIN_DIR/InlayApp" ] || fail "$BIN_DIR/InlayApp was not built."
[ -x "$BIN_DIR/$CLI_NAME" ] || fail "$BIN_DIR/$CLI_NAME was not built."

APP="build/$APP_NAME.app"
CLI="$APP/$CLI_PATH_IN_APP"

info "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/legal"
cp "$BIN_DIR/InlayApp" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$CLI_NAME" "$CLI"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp docs/config-examples/default-config.toml "$APP/Contents/Resources/default-config.toml"
cp LICENSE NOTICE.md "$APP/Contents/Resources/legal/"
cp -R legal/third-party-license "$APP/Contents/Resources/legal/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

PLIST="$APP/Contents/Info.plist"
cp Support/Info.plist "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
plutil -replace InlayGitHash -string "$GIT_HASH" "$PLIST"
plutil -lint "$PLIST" >/dev/null

# sign <identity>: the CLI first (it is nested code), then the bundle. Hardened runtime on both.
sign() {
  local keychain_args=()
  if [ "$1" != "-" ] && [ -n "$SIGN_KEYCHAIN" ]; then
    keychain_args=(--keychain "$SIGN_KEYCHAIN")
  fi
  # ${arr[@]+...}: bash 3.2 treats an empty array as unset under 'set -u'
  codesign --force --options runtime --timestamp=none ${keychain_args[@]+"${keychain_args[@]}"} \
    --identifier "$BUNDLE_ID.cli" --sign "$1" "$CLI" &&
    codesign --force --options runtime --timestamp=none ${keychain_args[@]+"${keychain_args[@]}"} \
      --sign "$1" "$APP"
}

if [ "$IDENTITY" = "-" ]; then
  info "Signing (ad hoc)"
  sign -
else
  info "Signing with \"$IDENTITY\""
  note "macOS may ask for the keychain password so that codesign can use the key: choose \"Always Allow\"."
  if ! sign "$IDENTITY"; then
    warn "signing with \"$IDENTITY\" failed. Falling back to an ad hoc signature:"
    warn "the Accessibility permission will have to be granted again after every rebuild."
    IDENTITY="-"
    sign -
  fi
fi

info "Verifying"
codesign --verify --strict --deep "$APP"
codesign --verify --strict "$CLI"
# The CLI must run and carry the sealed version. '--version' never starts the server: it prints the client
# version and, only if an Inlay server is already running, asks it for its own
CLI_VERSION="$("$CLI" --version 2>/dev/null || true)"
case "$CLI_VERSION" in
  *"$VERSION $GIT_HASH"*) ;;
  *) fail "the CLI doesn't report the version '$VERSION $GIT_HASH'." ;;
esac

info "Built $APP ($VERSION, $GIT_HASH, $([ "$IDENTITY" = "-" ] && echo "ad hoc signature" || echo "signed with \"$IDENTITY\""))"
