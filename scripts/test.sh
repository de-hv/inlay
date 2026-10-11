#!/usr/bin/env bash
#
# Runs the Swift Testing suite (Tests/InlayTests) using only the Xcode Command Line Tools.
#
#   scripts/test.sh                       run all the tests
#   scripts/test.sh --filter DwindleTest  the arguments are passed to 'swift test'
#
# It's 'swift test' with the toolchain of the Command Line Tools, even when xcode-select points to an Xcode.app.

set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

case "${1:-}" in
  -h|--help) sed -n '3,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
esac

use_command_line_tools

exec swift test "$@"
