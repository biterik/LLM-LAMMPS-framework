#!/usr/bin/env bash
# lint-no-identity.sh — compatibility wrapper.
#
# The real lint is canon/templates/lint-no-identity.py. It moved to Python
# on 2026-07-28: macOS ships bash 3.2 + BSD grep, which have neither
# `grep -P` nor reliable `case` inside `$(...)`, so the shell version ran
# only on Linux. A guard that runs on one machine is not a guard.
#
# This wrapper exists so `bash canon/templates/lint-no-identity.sh` keeps
# working. Prefer calling the .py directly.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/lint-no-identity.py" "$@"
