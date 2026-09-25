#!/usr/bin/env bash
# lint-handoff.sh -- check a command hand-off before it is sent to the user.
#
# Catches the three failure modes of L41 / preferences.md "Command hand-offs":
#   1. an unresolved <PLACEHOLDER> from the identity-scrubbed public canon
#   2. an ssh/scp/rsync/sshfs target with no user@, or with a cluster NAME
#      used where a hostname belongs
#   3. a fenced command block with no machine tag near it
#
# Usage:  canon/templates/lint-handoff.sh <file.md> [<file.md> ...]
# Exit:   0 = clean, 1 = at least one finding. Findings go to stderr.
#
# Written 2026-08-24 (L41), after a hand-off targeted `cmmg:` and tagged no
# block with a machine.
#
# SCOPE: run this over HAND-OFF TEXT -- the Runs section of a thread.md, a
# RESTART-BRIEF's command list, anything the user is meant to paste. Reference docs
# that merely CONTAIN example commands (canon/learnings.md, ARCHITECTURE.md,
# session-startup.md's `git clone <PRIVATE_OVERLAY_REPO>`) will fire on rule 3
# and sometimes rule 1, and that is expected -- an illustrative snippet needs no
# machine tag. Do not "fix" a reference doc to silence this lint.

set -uo pipefail
rc=0
CLUSTER_NAMES='cmmg|cmti|raven|viper|viper-cpu|viper-gpu'
MACHINE_TAG='MAC|M5|M2|M1|mini|SHELL|LOCAL SHELL|on the cluster|login node'

for f in "$@"; do
  [[ -r "$f" ]] || { echo "lint-handoff: cannot read $f" >&2; rc=1; continue; }

  # Work on a normalised copy: backslash-continuations joined onto one line, so
  # a multi-line rsync is matched as the single command it is. This is the shape
  # the 2026-08-24 miss actually had -- the `cmmg:` target sat two continuation
  # lines below the word `rsync`. Line numbers of the JOINED line are reported.
  awk '{ while (sub(/\\[[:space:]]*$/, "")) { if ((getline nxt) > 0) { sub(/^[[:space:]]+/, " ", nxt); $0 = $0 nxt } else break } print NR": "$0 }' "$f" > /tmp/lhj.$$

  # 1. unresolved placeholders -- only on COMMAND lines. Prose that discusses a
  # placeholder (this lint's own lesson text does) is not a finding.
  grep -E '^[0-9]+:[[:space:]]*(ssh|scp|rsync|sshfs|sbatch|srun|cd|git clone)[[:space:]]' /tmp/lhj.$$ \
    | grep -E '<CLUSTER_[A-Z_]+>|<PRIVATE_[A-Z_]+>|<SOMETHING>' > /tmp/lh.$$ || true
  if [[ -s /tmp/lh.$$ ]]; then
    echo "FAIL $f: unresolved placeholder in a command -- resolve from canon/local/clusters.local.yaml (L41)" >&2
    sed 's/^/    /' /tmp/lh.$$ >&2; rc=1
  fi

  # 2a. remote target without an explicit user@, on a real command line
  grep -E '^[0-9]+:[[:space:]]*(ssh|scp|rsync|sshfs)[[:space:]]' /tmp/lhj.$$ \
    | grep -E '[[:space:]][A-Za-z0-9._-]+:(/|~)|[[:space:]](ssh|sshfs)[[:space:]]+[A-Za-z0-9._-]+[[:space:]]*$' \
    | grep -vE '@' > /tmp/lh.$$ || true
  if [[ -s /tmp/lh.$$ ]]; then
    echo "FAIL $f: remote target without an explicit user@ (L21)" >&2
    sed 's/^/    /' /tmp/lh.$$ >&2; rc=1
  fi

  # 2b. a cluster NAME used where a hostname belongs
  grep -E '^[0-9]+:[[:space:]]*(ssh|scp|rsync|sshfs)[[:space:]]' /tmp/lhj.$$ \
    | grep -EI "[[:space:]@]($CLUSTER_NAMES):(/|~)|[[:space:]](ssh|sshfs)[[:space:]]+($CLUSTER_NAMES)[[:space:]]*$" > /tmp/lh.$$ || true
  if [[ -s /tmp/lh.$$ ]]; then
    echo "FAIL $f: a cluster NAME used as a hostname -- names are keys in clusters.yaml, hosts live in canon/local/ (L41)" >&2
    sed 's/^/    /' /tmp/lh.$$ >&2; rc=1
  fi

  # 3. command blocks with no machine tag within the 6 preceding lines
  awk -v tag="$MACHINE_TAG" '
    /^[[:space:]]*(sbatch|srun|ssh |rsync|scp |sshfs|squeue|sacct)/ {
      found=0
      for (i=1; i<=6; i++) if (prev[i] ~ tag) found=1
      if (!found) printf "%d: %s\n", NR, $0
    }
    { for (i=6; i>1; i--) prev[i]=prev[i-1]; prev[1]=$0 }
  ' "$f" > /tmp/lh.$$ || true
  if [[ -s /tmp/lh.$$ ]]; then
    echo "FAIL $f: command with no machine tag in the 6 lines above it (preferences.md, Command hand-offs)" >&2
    sed 's/^/    /' /tmp/lh.$$ >&2; rc=1
  fi

  rm -f /tmp/lh.$$ /tmp/lhj.$$
done

[[ $rc -eq 0 ]] && echo "lint-handoff: clean"
exit $rc
