#!/bin/bash
# lint-lammps-input.sh — Layer 1 pre-flight checks for LAMMPS input files
#
# Usage:   lint-lammps-input.sh <input-file>
# Exit:    0 if all checks pass; non-zero with diagnostics on first failure.
#
# Mechanizes ARCHITECTURE.md §12 Layer 1 checklist as encoded in
# <REPO_ROOT>/canon/style/lammps.md §1.1–1.5, 1.8, 1.16, 1.17-thermo (hard gates).
#
# Does NOT cover (still manual review required):
#   §1.4 MEAM library element index alignment with parameter file
#   §1.6 log directive position (first non-comment line)
#   §1.7 thermo cadence × expected iterations ≥ 1
#   §1.9 LAMMPS version doc-check
#
# Run as part of every pre-flight, before any submit.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <input-file>" >&2
  exit 2
fi

INPUT="$1"

if [[ ! -r "$INPUT" ]]; then
  echo "FAIL: cannot read $INPUT" >&2
  exit 2
fi

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "  ok: $1"
}

echo "Linting $INPUT ..."

# §1.1 — Runtime-quantity variable syntax (L1)
#   ${lx} etc. is parse-time string substitution; must be $(lx) for runtime evaluation.
if grep -nE '\$\{(lx|ly|lz|press|p[xyz]{2}|fnorm|fmax|etotal|step|temp|pe|ke|vol|enthalpy|cpu)\}' "$INPUT"; then
  fail "L1 — Runtime quantity referenced with \${...} (parse-time). Use \$(...) instead. See lines above."
fi
pass "L1 — no parse-time \${} on runtime quantities"

# §1.16 — ${} nested inside $(...) formulas (L44)
#   The parser never substitutes ${} inside an extracted $() formula; a '$'
#   is invalid equal-style syntax. Reference variables as v_name in formulas.
if grep -nE '\$\([^)]*\$\{' "$INPUT"; then
  fail "L44 — \${} substitution nested inside a \$(...) formula. Use v_name inside formulas (e.g. \$(ly/v_L)). See lines above."
fi
pass "L44 — no \${} nested inside \$(...) formulas"

# §1.17 — deleted ID still referenced by active thermo_style at an init (L45)
#   Join '&' continuations, then track: last thermo_style line; on
#   uncompute/unfix of an ID that line references, arm it; a later
#   thermo_style that drops the reference disarms; any init command
#   (run/minimize/write_data/write_restart/rerun) with an armed ID fails.
L45_OUT="$(awk '
  function refed(id) { return thermo ~ ("[cf]_" id "([^A-Za-z0-9_]|$)") }
  { line = $0
    while (line ~ /&[[:space:]]*$/) { sub(/&[[:space:]]*$/, " ", line); if ((getline nxt) > 0) line = line nxt; else break }
    $0 = line }
  /^[[:space:]]*thermo_style[[:space:]]/ {
    thermo = $0
    for (id in armed) if (!refed(id)) delete armed[id]
    next }
  /^[[:space:]]*(uncompute|unfix)[[:space:]]/ {
    if (thermo != "" && refed($2)) armed[$2] = NR
    next }
  /^[[:space:]]*(run|minimize|write_data|write_restart|rerun)([[:space:]]|$)/ {
    for (id in armed) { printf "line %d: init while thermo_style still references deleted ID %s (deleted near line %d)\n", NR, id, armed[id]; bad = 1 } }
  END { exit bad }' "$INPUT")" || {
  echo "$L45_OUT"
  fail "L45 — thermo_style references an uncomputed/unfixed ID at a system init. Reset thermo_style BEFORE the uncompute/unfix. See lines above."
}
pass "L45 — no deleted IDs dangling in thermo_style at an init"

# §1.2 — Generic filenames (L3, L20)
#   Match generic names only when standalone — preceded by start-of-line,
#   whitespace, '/', '=', or '"'. NOT preceded by '-' or other name chars,
#   which would indicate the generic token is a suffix of a descriptive name
#   (e.g., `Ni-fcc-Pezold-EAM-a0-result.txt` is fine, `a0-result.txt` is not).
GENERIC_PATTERN='(^|[[:space:]/="])(dump\.out|restart\.data|log\.lammps|a0-result\.txt|relaxation-log\.dat|final-snapshot\.dump|tmp\.|out\.dat|data\.lammps|dump\.atom|dump\.custom)([[:space:]"]|$)'
if grep -nE "$GENERIC_PATTERN" "$INPUT"; then
  fail "L3/L20 — generic filename(s) above. Use descriptive names (structure-observable-potential...). Exception: shell-script bookkeeping like start_time.txt is OK (and not in this lint)."
fi
pass "L3/L20 — no generic LAMMPS-tutorial-default filenames"

# §1.3 — ASCII-only (L2)
#   Use `file -i` if available; fall back to LC_ALL=C grep for non-ASCII bytes.
if command -v file >/dev/null 2>&1; then
  CHARSET="$(file -bi "$INPUT" | sed -n 's/.*charset=\([^;]*\).*/\1/p')"
  if [[ "$CHARSET" != "us-ascii" && "$CHARSET" != "binary" ]]; then
    fail "L2 — non-ASCII charset detected ($CHARSET). Check for em-dash, en-dash, curly quotes, greek letters, non-breaking space."
  fi
else
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$INPUT"; then
    fail "L2 — non-ASCII byte(s) above."
  fi
fi
pass "L2 — ASCII only"

# §1.13 — a fix wall/* face must sit on a NON-PERIODIC axis
#   LAMMPS: "Cannot use fix wall/reflect in periodic dimension z". Map each
#   wall face keyword (xlo/xhi/ylo/yhi/zlo/zhi) onto its axis, then read that
#   axis's char from the last `boundary` line. Killed 4 probe tasks 2026-08-25.
BOUNDARY_LINE=$(grep -E '^[[:space:]]*boundary[[:space:]]' "$INPUT" | tail -1 || true)
if [[ -n "$BOUNDARY_LINE" ]]; then
  read -r _kw BX BY BZ _rest <<<"$BOUNDARY_LINE"
  WALL_LINES=$(grep -nE '^[[:space:]]*fix[[:space:]]+.*[[:space:]]wall/' "$INPUT" || true)
  if [[ -n "$WALL_LINES" ]]; then
    while IFS= read -r wl; do
      [[ -z "$wl" ]] && continue
      for face in xlo xhi ylo yhi zlo zhi; do
        if grep -qE "(^|[[:space:]])${face}([[:space:]]|$)" <<<"$wl"; then
          case "${face:0:1}" in
            x) bc="$BX" ;;
            y) bc="$BY" ;;
            z) bc="$BZ" ;;
          esac
          # a boundary char may be doubled (`pp`, `fs`); a wall needs the axis
          # non-periodic on the relevant side, so reject any p in the field.
          case "$bc" in
            *p*) fail "1.13 — 'fix wall/*' acts on face ${face} but 'boundary' gives '${bc}' for that axis. LAMMPS rejects a wall in a periodic dimension at init; set the axis to f (or s/m) in the SAME edit. Offending line: ${wl}" ;;
          esac
        fi
      done
    done <<<"$WALL_LINES"
  fi
  pass "1.13 — no fix wall/* on a periodic axis"
fi

# §1.5 — fix print not used inside minimize block (L5)
#   Scan the lines between the first `minimize` and the next `run` or EOF.
#   If any `fix ... all print ...` appears in that range, fail.
awk '
  BEGIN { in_block = 0 }
  /^[[:space:]]*minimize[[:space:]]/ { in_block = 1; next }
  /^[[:space:]]*run[[:space:]]/      { in_block = 0 }
  in_block && /^[[:space:]]*fix[[:space:]]+\S+[[:space:]]+\S+[[:space:]]+print[[:space:]]/ {
    print NR": "$0; found = 1
  }
  END { exit (found ? 1 : 0) }
' "$INPUT" || fail "L5 — \`fix print\` appears inside a minimize-active region. fix print does not fire during minimize iterations; use thermo_style custom with equal-style variables instead."
pass "L5 — no fix print inside minimize block"

# §1.6 — log directive present + first non-comment line
LOG_LINE=$(awk '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  { print NR": "$0; exit }
' "$INPUT")
if ! echo "$LOG_LINE" | grep -qE '^\s*[0-9]+:\s*log\s+\S+'; then
  echo "WARN: first non-comment line is not a \`log <file>\` directive:" >&2
  echo "      $LOG_LINE" >&2
  echo "      L6 says log filename should be set at the very top. Continuing." >&2
fi
# (warn only — not all inputs follow this; minimization-only might not need it)

# §1.8 — Placeholder substitution check
#   Find ALL CAPS bare tokens >= 3 chars that aren't known LAMMPS keywords.
#   This is a heuristic; report rather than fail.
KNOWN_CAPS='NVE|NVT|NPT|NPH|MEAM|EAM|REAXFF|TERSOFF|MORSE|LJ|FCC|BCC|HCP|SC|PE|KE|CG|SD|FIRE|HFTN|SI|CGS|REAL|METAL|ATOMIC|CHARGE|FULL|BOND|ANGLE|DIHEDRAL|IMPROPER'
SUSPECTS=$(grep -nE '\b[A-Z][A-Z0-9_]{2,}\b' "$INPUT" \
  | grep -vE "\\b(${KNOWN_CAPS})\\b" \
  || true)
if [[ -n "$SUSPECTS" ]]; then
  echo "WARN: potential unsubstituted ALL CAPS placeholders (review manually):" >&2
  echo "$SUSPECTS" | head -20 >&2
fi

echo "All mechanical checks passed for $INPUT."
exit 0
