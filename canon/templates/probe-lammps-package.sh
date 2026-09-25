#!/bin/bash
# erik, 2026-05-31
#
# Probe whether a specified LAMMPS package is built into a specified
# module. Runs `lmp -h` and greps the installed-packages block.
#
# Cheap — runs on the cluster login node, no sbatch needed.
#
# Usage:
#   ./probe-lammps-package.sh <module> <PACKAGE-NAME>
#
# Examples:
#   ./probe-lammps-package.sh lammps/250722 EXTRA-COMPUTE
#   ./probe-lammps-package.sh lammps/241119 MEAM
#
# Exit 0 if built, 1 if not.

set -euo pipefail

MODULE="${1:?usage: $0 <module> <PACKAGE-NAME>}"
PACKAGE="${2:?usage: $0 <module> <PACKAGE-NAME>}"

module purge
module load "$MODULE"

LMP_BIN="${LMP_BIN:-lmp}"

# `lmp -h` writes its full help (including the Installed packages list)
# to stdout. -w = whole-word match (so "EXTRA-COMPUTE" doesn't match
# "EXTRA-COMPUTE-EXT" or similar hypothetical names).
LMP_HELP="$("$LMP_BIN" -h 2>&1)"

if echo "$LMP_HELP" | grep -qw "$PACKAGE"; then
    echo "BUILT: $PACKAGE is present in $MODULE"
    exit 0
else
    echo "MISSING: $PACKAGE is NOT built into $MODULE"
    echo "---"
    echo "Diagnostic dumps (so we can verify the probe ran correctly):"
    echo
    echo "[a] First 120 lines of \`lmp -h\` (covers metadata + packages):"
    echo "$LMP_HELP" | head -120
    echo
    echo "[b] Any line matching 'package' or 'EXTRA':"
    echo "$LMP_HELP" | grep -iE 'package|extra' | head -30
    exit 1
fi
