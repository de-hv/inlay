#!/usr/bin/env bash
#
# Runs the Swift Testing suite (Tests/InlayTests) using only the Xcode Command Line Tools.
#
#   scripts/test.sh                       run all the tests
#   scripts/test.sh --filter DwindleTest  the arguments are passed to 'swift test'
#
# It's 'swift test' plus a workaround: after the sources of the app change, an incremental build of the test
# target may fail with "plugin for module 'TestingMacros' not found" (the compiler isn't told where the macros
# of Swift Testing are). Building the test target from scratch always works, so its build products are removed
# first. The rest of the build stays incremental.

set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

case "${1:-}" in
  -h|--help) sed -n '3,11s/^# \{0,1\}//p' "$0"; exit 0 ;;
esac

use_command_line_tools

find .build -type d -name 'InlayTests*.build' -prune -exec rm -rf {} + 2>/dev/null || true
exec swift test "$@"
