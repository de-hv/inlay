#!/usr/bin/env bash
#
# Regenerates Support/AppIcon.icns from scripts/icon/AppIcon.swift.
#
#   scripts/make-icon.sh
#
# Only needed after changing the drawing: the .icns is committed, so a normal build doesn't run this.

set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh
use_command_line_tools

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/AppIcon.iconset"
MASTER="$WORK/AppIcon-1024.png"
mkdir -p "$ICONSET"

info "Drawing the icon"
swift scripts/icon/AppIcon.swift "$MASTER"

info "Building the iconset"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Support
iconutil --convert icns "$ICONSET" --output Support/AppIcon.icns

info "Wrote Support/AppIcon.icns"
