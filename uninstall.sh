#!/usr/bin/env bash
# Shortcut for scripts/uninstall.sh. See that file, or run: ./uninstall.sh --help
exec "$(dirname "$0")/scripts/uninstall.sh" "$@"
