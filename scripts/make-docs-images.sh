#!/bin/bash
# Regenerates the images of the README in docs/images from their sources in docs/images/src:
#
#   - the real renders of the app (menu bar item, borders, Settings), drawn off screen by build/Inlay.app
#     with --render-menu-bar, --render-borders and --render-settings. The app is not started as the window manager
#   - the sheets that gather those renders with their captions, and the illustrations: HTML pages turned into PNG
#     files by a headless Chrome
#   - the animations: HTML pages whose frames gif.swift turns into GIF files
#
# Usage: scripts/make-docs-images.sh [--no-build] [name ...]     (without names: all the images)
#
# It needs Google Chrome and the Xcode Command Line Tools. Nothing is installed, and Inlay, its config and
# /Applications are not touched. The renders show the accent color of this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SRC="$PWD/docs/images/src"
OUT="$PWD/docs/images"
WORK="$SRC/render" # Not in git: the renders of the app, the sprites and the gif tool
APP="$PWD/build/Inlay.app/Contents/MacOS/Inlay"

build=1
names=()
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) names+=("$arg") ;;
  esac
done
wanted() { [ ${#names[@]} -eq 0 ] || [[ " ${names[*]} " == *" $1 "* ]]; }

[ -x "$CHROME" ] || { echo "error: Google Chrome not found at $CHROME (set CHROME=...)" >&2; exit 1; }
if [ "$build" = 1 ]; then
  scripts/build-app.sh --sign-identity - >/dev/null 2>&1 || { echo "error: scripts/build-app.sh failed: run it to see why" >&2; exit 1; }
fi
[ -x "$APP" ] || { echo "error: $APP not found: run it without --no-build" >&2; exit 1; }

# --- The real renders ---
mkdir -p "$WORK"
"$APP" --render-menu-bar "$WORK/menu-bar" >/dev/null
"$APP" --render-menu-bar "$WORK/menu-bar-6x" 6 >/dev/null
"$APP" --render-borders "$WORK/borders" >/dev/null
"$APP" --render-settings "$WORK/settings" >/dev/null
# The Borders tab with other values of 'width', for the animation of the file and the window in sync
for width in 2 8; do
  sed "s/^    width = 4\$/    width = $width/" inlay.toml >"$WORK/width-$width.toml"
  "$APP" --render-settings "$WORK/settings-width-$width" "$WORK/width-$width.toml" >/dev/null
done
for tab in general themes tiling gaps animations menu-bar borders; do
  if wanted "settings-$tab"; then cp "$WORK/settings/settings-$tab.png" "$OUT/settings-$tab.png"; echo "settings-$tab.png"; fi
done

chrome() { # chrome <width> <height> <scale> <more options...>
  local width=$1 height=$2 scale=$3
  shift 3
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --allow-file-access-from-files \
    --user-data-dir="$WORK/chrome-profile" --force-device-scale-factor="$scale" --window-size="$width,$height" \
    --default-background-color=00000000 --virtual-time-budget=3000 "$@" 2>/dev/null
}

# --- PNG: name:width:height (in points; rendered at 2x) ---
PAGES=(
  hero:1280:800
  menu-bar-themes:880:700
  menu-bar-palettes:880:1170
  menu-bar-states:880:330
  menu-bar-options:880:476
  menu-bar-colors:880:500
  menu:880:400
  borders-states:880:586
  borders-width:880:290
  borders-corner-radius:880:310
  borders-glow:880:310
  borders-gaps:880:310
  terminal-install:880:914
  terminal-cli:880:486
  terminal-uninstall:880:462
)
for page in "${PAGES[@]}"; do
  IFS=: read -r name width height <<<"$page"
  wanted "$name" || continue
  chrome "$width" "$height" 2 --screenshot="$OUT/$name.png" "file://$SRC/$name.html" >/dev/null
  echo "$name.png  ${width}x${height}@2x"
done

# --- GIF ---
ANIMATIONS=(tiling-dwindle tiling-startup-layout tiling-split-target tiling-split-ratio tiling-min-window-size
  tiling-minimize gaps settings-sync)
gif_tool="$WORK/gif"
if [ ! -x "$gif_tool" ] || [ "$SRC/gif.swift" -nt "$gif_tool" ]; then
  swiftc -O "$SRC/gif.swift" -o "$gif_tool"
fi
for name in "${ANIMATIONS[@]}"; do
  wanted "$name" || continue
  chrome 800 600 1 --dump-dom "file://$SRC/$name.html?meta" | sed -n 's/.*@@\(.*\)@@.*/\1/p' >"$WORK/$name.json"
  read -r width height < <(sed -E 's/.*"w":([0-9]+),"h":([0-9]+).*/\1 \2/' "$WORK/$name.json")
  frames=$(sed -E 's/.*"delays":\[([^]]*)\].*/\1/' "$WORK/$name.json" | tr ',' '\n' | wc -l)
  sprites=()
  for ((i = 0; i * 16 < frames; i++)); do # 16 frames per screenshot, in 2 rows of 8, at 2x
    sprites+=("$WORK/$name-sprite-$i.png")
    chrome $((width * 8)) $((height * 2)) 2 --screenshot="$WORK/$name-sprite-$i.png" "file://$SRC/$name.html?sprite=$i" >/dev/null
  done
  "$gif_tool" "$WORK/$name.json" "$OUT/$name.gif" "${sprites[@]}" | sed "s|$OUT/||"
done
