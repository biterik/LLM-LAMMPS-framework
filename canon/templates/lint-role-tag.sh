#!/usr/bin/env bash
# erik (LLM-LAMMPS designer), 2026-06-01
#
# lint-role-tag.sh — enforce the single-hat response-tag rule.
# Every response is tagged with EXACTLY ONE hat: `**[Pilot]**` or
# `**[Designer]**`. The combined token `[Designer+Pilot]` is BANNED as a
# response tag; `designer+pilot` (no brackets) is only a SESSIONS.md
# session *capability*. See ARCHITECTURE.md §17.5.
#
# Why this exists: the 2026-06-01 Ni-hydride incident was NOT a dropped
# tag — the canon itself had sanctioned `[Designer+Pilot]` as a valid
# response tag, so following canon produced the violation the user rejected.
# This lint stops the bracketed combined token from creeping back into
# canon as if it were a usable tag.
#
# Implements "fix the class, not the instance" (canon/learnings.md
# "Process"): the role-tag rule was changed canon-wide; this guards it.
#
# What it flags: any line containing the bracketed token `[Designer+Pilot]`
#   (in any markdown/yaml/sh/skel canon file) that is NOT explicitly marked
#   as a deliberate reference. A line that legitimately NAMES the banned
#   tag (to define or forbid it) must carry the inline marker:
#       lint-ok:role-tag
#   Lines without that marker are treated as an attempt to re-introduce the
#   combined tag and fail the lint.
#
# Note — the companion behavioral rule "Pilot wait-and-co-develop"
#   (canon/learnings.md hard rules) is NOT greppable and has no lint;
#   adherence is its only lever, same as lessons L28-L30.
#
# EXEMPT files (historical audit / append-only; do not rewrite history):
#   - SESSIONS.md                 (mode/audit lines)
#   - canon/proposals-inbox.md    (merged-entry bodies, append-only audit)
#   - .retired-CHECKPOINT.md      (retired snapshot)
#   - brainstorm-notes.md         (design-history notes)
#   - data-*/conversations.json   (raw transcript dump)
#
# Usage: run from repo root.  Exit 0 = clean, 1 = unmarked combined tag.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root (canon/templates/ -> repo)

hits=$(grep -rnE '\[Designer\+Pilot\]' \
  --include='*.md' --include='*.yaml' --include='*.sh' --include='*.skel' \
  --exclude='SESSIONS.md' \
  --exclude='proposals-inbox.md' \
  --exclude='.retired-CHECKPOINT.md' \
  --exclude='brainstorm-notes.md' \
  --exclude='lint-role-tag.sh' \
  . 2>/dev/null | grep -v 'lint-ok:role-tag' || true)

if [[ -n "$hits" ]]; then
  echo "Unmarked combined [Designer+Pilot] tag found (banned as a response tag):"
  echo "$hits"
  echo
  echo "Every response is tagged with exactly one hat: [Pilot] OR [Designer]."
  echo "If a hit deliberately NAMES the banned tag (to define/forbid it),"
  echo "append the inline marker  lint-ok:role-tag  to that line."
  exit 1
fi
echo "clean — no unmarked [Designer+Pilot] response tags."
exit 0
