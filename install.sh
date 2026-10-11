#!/usr/bin/env bash
# Shortcut for scripts/install.sh. See that file, or run: ./install.sh --help
exec "$(dirname "$0")/scripts/install.sh" "$@"
