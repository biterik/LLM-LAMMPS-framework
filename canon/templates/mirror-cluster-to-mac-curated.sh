#!/bin/bash
# erik, 2026-05-31
#
# Pull the CURATED set from a cluster-side thread dir to its Mac
# counterpart. Mac is the durable archive; cluster keeps everything
# (logs, slurm noise, AppleDouble) for debugging. This script does NOT
# do a kitchen-sink rsync.
#
# What it pulls:
#   - *.in           LAMMPS inputs
#   - *.slurm        Submit scripts
#   - *.py           Analysis / driver scripts
#   - *.dat          Aggregated result tables (stress-strain, born-matrix)
#   - *.yaml         Provenance / summary / mile-pebble metadata
#   - *.md           thread.md, project.md, comparison reports
#   - *.pdf          Plots, comparison charts
#
# What it does NOT pull (deliberately):
#   - per-iteration LAMMPS *.log files
#   - log.lammps residual
#   - start_time.txt, end_time.txt
#   - slurm *.err / *.out
#   - macOS AppleDouble sidecars (._*) and .DS_Store
#   - __pycache__/
#   - structure *.data / *.data.zst / *.dump (these need ASK-FIRST
#     handling; use the separate sync-structures-to-mac.sh helper
#     once the user confirms, or do an explicit one-off cp with zstd -19
#     compression per the Thread-01 mile-pebble pattern)
#
# Usage:
#   ./mirror-cluster-to-mac-curated.sh <cluster-thread-dir> <mac-thread-dir>
#
# Example:
#   ./mirror-cluster-to-mac-curated.sh \
#     ~/cluster-mounts/cmmg/Ni-A0-CIJ-EAM-MEAM/02_ELASTIC-CONSTANTS-AT-0K \
#     ~/Desktop/SIMULATIONS/Ni-A0-CIJ-EAM-MEAM/02_ELASTIC-CONSTANTS-AT-0K

set -euo pipefail

CLUSTER="${1:?usage: $0 <cluster-thread-dir> <mac-thread-dir>}"
MAC="${2:?usage: $0 <cluster-thread-dir> <mac-thread-dir>}"

[[ -d "$CLUSTER" ]] || { echo "Cluster path not found (mount missing?): $CLUSTER" >&2; exit 1; }
[[ -d "$MAC"     ]] || { echo "Mac path not found: $MAC" >&2; exit 1; }

# Filter rules:
#   - include subdirs (so rsync recurses)
#   - include only the curated extensions
#   - exclude everything else (catch-all)
# First-match-wins for rsync, so the includes hit before the final exclude='*'.

rsync -rtv --safe-links \
  --include='*/' \
  --include='*.in' \
  --include='*.slurm' \
  --include='*.py' \
  --include='*.dat' \
  --include='*.yaml' \
  --include='*.md' \
  --include='*.pdf' \
  --exclude='*' \
  "$CLUSTER/" "$MAC/"

echo
echo "Curated mirror complete."
echo "Reminder: structure files (.data, .data.zst, .dump) need explicit"
echo "ASK-and-cp with zstd -19 compression — they are NOT mirrored by"
echo "this helper. See canon/learnings.md (Cluster discipline)."
