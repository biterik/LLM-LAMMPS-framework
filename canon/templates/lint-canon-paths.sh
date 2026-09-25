#!/usr/bin/env bash
# erik (LLM-LAMMPS designer), 2026-06-01
#
# lint-canon-paths.sh — flag stale references to the OLD hidden canon
# directory `.lmps/`. The canon was renamed `.lmps/` -> `canon/` (visible)
# on 2026-06-01; see ARCHITECTURE.md §6. New normative/forward-looking text
# must say `canon/`, never `.lmps/`.
#
# Implements the "fix the class, not the instance" discipline
# (canon/learnings.md "Process"): the rename was a class-wide change, and
# this lint stops the old path from creeping back in.
#
# What it flags: a live PATH reference into the old canon dir — `.lmps/`
#   followed by a path component (a filename, sub-dir, or `*`), e.g.
#   `.lmps/lessons.md`, `.lmps/style/`, `.lmps/*`. It does NOT flag:
#   - the LAMMPS data-file EXTENSION `.lmps` (no slash, e.g. `Ni-fcc.lmps`)
#   - bare prose MENTIONS of the rename where `.lmps/` is followed by a
#     backtick/space/punctuation (e.g. "renamed from the former `.lmps/`").
#
# EXEMPT files (legitimately retain historical `.lmps/` as audit of past
# sessions; do not rewrite history):
#   - SESSIONS.md                 (## recently_closed entries)
#   - canon/proposals-inbox.md    (merged-entry bodies, append-only audit)
#   - .retired-CHECKPOINT.md      (retired snapshot)
#   - brainstorm-notes.md         (2026-06-01 decision block cites the old
#                                  path on purpose to record the rename)
#   - data-*/conversations.json   (raw transcript dump)
#
# Usage: run from repo root.  Exit 0 = clean, 1 = stale refs found.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root (canon/templates/ -> repo)

hits=$(grep -rnE '\.lmps/[A-Za-z*]' \
  --include='*.md' --include='*.yaml' --include='*.sh' --include='*.skel' \
  --exclude='SESSIONS.md' \
  --exclude='proposals-inbox.md' \
  --exclude='.retired-CHECKPOINT.md' \
  --exclude='brainstorm-notes.md' \
  --exclude='lint-canon-paths.sh' \
  . 2>/dev/null || true)

if [[ -n "$hits" ]]; then
  echo "STALE .lmps/ directory references found (should be canon/):"
  echo "$hits"
  echo
  echo "If a hit is legitimate historical audit, add its file to the"
  echo "EXEMPT list in this script's header and the --exclude flags above."
  exit 1
fi
echo "clean — no stale .lmps/ directory references."
exit 0
