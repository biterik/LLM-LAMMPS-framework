# LLM-LAMMPS — Style guide for LAMMPS inputs

**Pilot must walk this file top-to-bottom before any LAMMPS input Write.**
This is the materialization of ARCHITECTURE.md §12 Layer 1 pre-flight,
the descriptive-names rule (architecture §2 rule 2), and the lessons in
`../lessons.md`.

---

## 1. Pre-flight checklist (Layer 1, literal, grep-able)

Run this list **on the input source as it stands just before Write**.
Each item is either a shell command that should return nothing / report
the expected charset, or a manual check. If any item fails, fix before
writing; do not submit and let Layer 2 catch it.

### 1.1 Variable-syntax check (L1)

```
grep -E '\$\{(lx|ly|lz|press|p[xyz]{2}|fnorm|fmax|etotal|step|temp|pe|ke)\}' <input>
```

Must return nothing. These are runtime quantities — they need `$(...)`
(equal-style evaluation), not `${...}` (immediate substitution).

### 1.2 Generic-filename check (L3, L20)

```
grep -E '(^|[[:space:]/="])(dump\.out|restart\.data|log\.lammps|a0-result\.txt|relaxation-log\.dat|final-snapshot\.dump|tmp\.|out\.dat|data\.lammps)([[:space:]"]|$)' <input>
```

Must return nothing. **The leading and trailing anchors are load-bearing:** the
offence is a filename that IS the tutorial default, not one that ends with it.
`Ni-fcc-Pezold-EAM-final-snapshot.dump` is correct and must not be flagged; a
bare `final-snapshot.dump` must be. The pre-2026-08-03 pattern opened with
`(^|[^A-Za-z])`, which a leading `-` satisfies, so it flagged every
descriptively-prefixed name -- including the canonical idiom this same file
recommends in section 3. `templates/lint-lammps-input.sh` already carried the
anchored form; only this document was stale. Every output filename must encode at minimum
structure + observable + potential context (e.g.,
`Ni-fcc-10x10x10-a0-min-Pezold-EAM.data`,
`Ni-fcc-Cij-strain-axial-1e-3-MEAM-KoShimLee.log`).

Manual companion: grep for every output-producing command and inspect
each filename:

```
grep -E '^(log|write_data|write_restart|dump|fix\s+\S+\s+all\s+print|fix\s+\S+\s+all\s+ave/time|fix\s+\S+\s+all\s+ave/chunk)' <input>
```

### 1.3 ASCII-only check (L2)

```
file -i <input>
```

Must report `charset=us-ascii`. No em-dash, en-dash, curly quotes,
greek letters, non-breaking space. Even in comments.

### 1.4 MEAM library element list (L4)

`pair_coeff` syntax for MEAM has two element lists:

```
pair_coeff * * <library> <elem-list-1> <param-file> <elem-list-2>
```

`<elem-list-1>` = elements to extract from the library; the parameter
file's `(i,j)` index references resolve against this list.
`<elem-list-2>` = atom-type to element-name mapping (length = number
of atom types).

Check:
- Open the parameter file. Grep for any `(i,j)` or `(i)` index
  reference. Max(i,j) determines minimum length of `<elem-list-1>`.
- `<elem-list-1>` must include every element the param file references
  by index, even if the simulation has no atoms of that species.
- `<elem-list-2>` lists the atoms you do have, mapped to names that
  appear in `<elem-list-1>`.

Example — pure-Ni minimization with the Ni-H Ko-Shim-Lee MEAM:

```
pair_coeff * * ${POTDIR}/${POTENTIAL_LIB} Ni H ${POTDIR}/${POTENTIAL_PAR} Ni
```

Not lint-automatable (requires reading the parameter file). Manual.

### 1.5 `fix print` not during minimize (L5)

```
awk '/^minimize/,/^run|^$/' <input> | grep -E '^fix\s+\S+\s+\S+\s+print'
```

Must return nothing. If a per-iteration printout is needed during
minimize, use a custom `thermo_style` column referencing an equal-style
variable — not `fix print`. General rule: for any fix used during
minimize, consult the fix's doc page for the "supported during minimize?"
note before assuming it fires.

### 1.6 Log filename + screen-redirect convention (L6)

The very first non-comment line of the input must be:

```
log <descriptive>.log
```

The companion submit script must include `-screen none` in the srun
invocation so LAMMPS doesn't double-print to the slurm `.out`.

### 1.7 Thermo cadence × expected iterations ≥ 1

If `thermo N` with `N > expected_max_iterations`, the log will contain
zero time-series rows. Sanity check the cadence against the expected
minimize / run length.

### 1.8 Placeholder substitution

If the input is rendered from a skeleton with ALL CAPS placeholders
(STRUCTURE, FUPPER, etc., per `learnings.md` LAMMPS-specific section):

```
grep -E '\b[A-Z][A-Z0-9_]{2,}\b' <input>
```

Inspect output for any remaining placeholder tokens that should have
been substituted. False positives are common (LAMMPS keywords like
`NVE`, `MEAM`); the pilot reads, doesn't blindly trust the grep.

### 1.11 No `thermo` doubling when a dedicated dump file exists (L27)

If the input has a `fix print` or `fix ave/time` writing thermo-like
quantities to a named .dat file (the canonical record for downstream
plotting/analysis), the `thermo N` cadence must be set high enough that
no in-loop thermo rows are emitted to the LAMMPS log — only the
unsuppressable run-start and run-end blocks.

Practical threshold: `thermo N` with N >= the highest single-`run` step
count in the input (or any safely-large number like 1000000). LAMMPS
has no "off" switch for in-loop thermo; this is the canonical
work-around.

Grep:

```
grep -E '^thermo +[0-9]+' <input>
```

Read each match. If the input also has a `fix print` or `fix ave/time`
writing thermo channels to a `.dat`, the `thermo` N must be larger than
the largest `run` count. Fail otherwise.

### 1.10 `if` boolean operand sanity (L25)

For every `if "..."` line in the input, the operand strings around
comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`) must contain
only `[A-Za-z0-9_]`. The LAMMPS Boolean expression tokenizer splits
on `+`, `-`, `*`, `/`, etc. *before* deciding numeric-vs-string, so
operands like `axial-xx` get parsed as `axial − xx` and abort with
`ERROR: Invalid Boolean syntax in if command`. Quoting the operand
inside the Boolean does NOT help — per LAMMPS docs the operands must
not be enclosed in quotes inside the Boolean expression.

Grep:

```
grep -E '^if[[:space:]]+"' <input> | grep -E '[A-Za-z][A-Za-z0-9]*[-+*/^][A-Za-z0-9]'
```

Must return nothing (or only legitimate math expressions where the
operator characters are intended). When in doubt, read each `if` line
and confirm operand strings are pure alphanumerics + underscores.

### 1.9 LAMMPS version doc-check

Every command line the session **writes or edits** is checked against the docs
of the LAMMPS version currently loaded on the target cluster (recorded in
`clusters.yaml` and in the run's submit script) -- not the latest stable, and
not a remembered version. **There is no exempt class of command.** The previous
wording named `fix`, `compute` and `pair_style`, which read as a whitelist and
quietly exempted the structural commands -- `group`, `velocity`, `set`,
`delete_atoms`, `region` -- whose very familiarity suppresses the lookup. A
line you did not touch needs no check; a line you typed does, however boring
the command looks. (Rewritten 2026-08-20 after L40.)

**Check the preconditions, not just the spelling.** A command can be spelled
correctly, appear verbatim in the syntax block, and still be invalid in the
state the script has put the system in. When reading a doc page, read for:

- does this require the group / fix / compute / region / box to already
  **exist**? (`group ID clear` and `group ID delete` both do -- L40;
  `region ... INF` needs a box created first)
- is it legal **during minimize**? (L5)
- does it depend on **ordering** relative to another command? (L37:
  `reset_timestep` after a gcmc-like fix silently disarms it)
- does it behave the same for a **group other than `all`**? (L38)

**Keyword invention is a real but secondary risk.** A keyword that reads
naturally ("clear", "reset", "none") is not evidence that the command accepts
it, and LAMMPS spells the same concept differently per command (`group ...
delete`, `velocity ... zero`, `unfix`). When the keyword is a verb you supplied
rather than one you read, look it up. Note, though, that a hardcoded
allow-list of keywords is NOT the remedy: names change between versions (L8),
so the list goes stale and buys false confidence. Read the doc page for the
loaded version -- that is the whole rule.

### 1.12 `print` / `fix print` argument sanity (L30, L31)

Two distinct failure modes, both surfacing as
`ERROR: Incorrect conversion in format string (src/input.cpp:649)`:

- **L31 — `%d`/`%i`/`%x` inside `$(...)`**: LAMMPS evaluates `$(expr)`
  as a double, so an integer conversion is illegal. Affects BOTH
  `print` and `fix print`. Use bare `$(step)` (default `%.20g`, prints
  integral values exactly) or `$(step:%.0f)`. Float quantities
  (`$(temp:%.3f)`, `$(lx:%.6f)`) are fine.
- **L30 — bare `%` in a standalone `print`**: a `%` not inside a
  `$(...)` is read as a printf conversion with no matching argument and
  fails at parse time. Keep standalone `print` strings static, or use
  `$(quantity)` / `${var}`.

Grep (read each hit; confirm intent):

```
# L31: integer conversion inside $(...) — must return nothing
grep -nE '\$\([^)]*:%[0-9.]*[diuxX]\)' <input>
# L30: % outside any $(...) in a standalone print — inspect each
grep -nE '^[[:space:]]*print[[:space:]]' <input> | grep -F '%'
```

The first grep must return nothing. The second is a read-and-confirm:
any `%` in a standalone `print` line should sit inside a `$(...)` with
a float format, otherwise reject.

---

### 1.13 Boundary conditions against the stated design

Read the `boundary` line and check it against what the user specified for THIS run,
not against what the template had. State the boundary conditions back to him in
words in the design summary ("periodic in x and y, reflecting wall at the top,
bottom three layers frozen") before any submit.

**Vacuum across a periodic axis is not a free surface.** If an axis is periodic
and the cell contains a vacuum gap, the two faces of the slab are connected
through it: anything desorbing from one surface re-enters at the other. A
cleanup fix is NOT equivalent to a wall. If one is used anyway, its region must
span the whole gap, and its interval must be short compared with the transit
time of the lightest species across that gap -- for H at 300 K, ~27 A/ps, so a
50 A gap is crossed in ~2 ps.

```
grep -nE '^boundary' <input>
grep -nE 'fix .*(wall/reflect|evaporate)|^region .*(VAC|vac)' <input>
```

If `boundary` has `p` on an axis that has vacuum on it, either there is a wall
or there is a defect. Read which. See L41.

**A wall is not a patch on a periodic axis -- it REQUIRES the axis
non-periodic.** If a `fix wall/*` acts in dimension D, the boundary in D must
be `f` (or `s`/`m`). LAMMPS rejects the combination at init:

```
ERROR: Cannot use fix wall/reflect in periodic dimension z
(src/fix_wall_reflect.cpp:110)
```

The two halves of the previous paragraph therefore travel together: when a wall
is added to close the L41 vacuum-gap hole, **change the boundary in the same
edit**. `p` plus a wall is not a stricter version of `p` -- it is a job that
dies in the first second. Changing the axis to `f` is also the honest geometry:
the slab's faces become genuinely disconnected, which is what the wall was for.

Where it bit: 2026-08-25, ni-h-hydride-cycle-eam threads 03 and 04. A
reflecting wall at 134 a0 was added to fix the L41 re-entry while `boundary p p
p` stayed. All four probe tasks (`22728943_[0-1]`, `22728944_[0-1]`) died at
init. The command had been doc-checked for SYNTAX but not for this
PRECONDITION -- the class §1.9 exists to catch. Mechanically linted since
2026-08-26; see `templates/lint-lammps-input.sh`.

### 1.18 A barostat remaps EVERY atom by default (`dilate all`)

`fix npt` / `fix nph` and friends default to `dilate all`: the box remap is
applied affinely to every atom in the cell, including atoms in a group you
believe you are holding still. `velocity ... zero` and `fix setforce 0 0 0`
stop a group's *dynamics*; they do not exempt it from the *remap*. A "frozen"
substrate under a barostatted region is therefore strained silently, by exactly
the box strain.

Restrict the remap to the mobile group, and define the barostat on it:

```
fix MELT HOT nph x <...> dilate HOT       # not `dilate all`
```

(The `dilate <group>` example in `fix_nh.html` is precisely this case: a solid
substrate under a barostatted fluid.)

**Corollary, and the half that costs more: "held fixed" is a QUANTITATIVE
probe gate.** Verify it from the probe snapshot against a number you already
know -- layer spacing against a0/2, or displacement against the reference
configuration -- never from a picture, and never from an fcc percentage, which
is invariant under a uniform strain and will happily report a perfect crystal.

Where it bit: 2026-08-25, ni-melting-point-eam thread 01, prepare probe attempt
2. EVERY mechanical gate passed -- ALL PHASES COMPLETE, clean `.err`, hot half
molten -- while the "frozen" cold half sat at 8 % uniaxial strain: x layer
spacing 1.94 A against a0/2 = 1.794 A, exactly the box expansion. The
layer-spacing histogram settled in one pass what four green gates had missed.

### 1.19 A held rigid crystal template ORDERS the liquid beside it

Any stage that equilibrates a liquid against a HELD (rigid) crystal template
must budget for epitaxial and confinement freezing. A commensurate liquid film
thinner than ~2-3 nm between template faces -- **and periodicity counts as the
second face** -- can crystallize ABOVE the bulk melting point, because the
ordering reach of each wall is ~1 nm and the two reaches meet.

Rules: check the film thickness against that reach before trusting any stage
that holds a template; keep such stages to the few-ps minimum; or thermalize
the template instead of freezing it. If the geometry cannot avoid it, the
observable must be measured somewhere the template's reach does not arrive.

Where it bit: 2026-08-25, ni-melting-point-eam. A guarded settle froze a 15 A
liquid film at EVERY rung of the cube ladder; the full 7-rung production then
measured cells whose liquid had already crystallized (transverse-order minimum
0.38-0.54 in every final configuration, no melting even at 1600 K). See the
Workflow rule "A gate is a mechanism, not a sign" in `../learnings.md` -- this
rule is its physical half.

### 1.14 Per-atom stress and energy at finite T

A single-snapshot per-atom stress or energy at finite temperature is dominated
by thermal fluctuation and is not a field. If the input writes per-atom
stresses or energies for analysis, it must also say how the noise is handled,
and thread.md records which:

- **inline time-averaging** -- `compute stress/atom` / `compute pe/atom`
  through `fix ave/atom`, over a window long compared with the phonon period
  (~0.1-1 ps) and short compared with the evolution of the field; or
- **a short `quickmin`/FIRE quench** of saved snapshots at FIXED box, then
  compute on the inherent structure. L12 forbids pairing those minimizers with
  `fix box/relax`, and a stress map wants the box held anyway -- relaxing it
  would discard the coherency stress being measured.

Usually do both: averaged fields inline so something usable always exists, plus
enough full snapshots retained that a quench pass is possible later.

**`compute stress/atom` returns stress x volume, not stress.** Divide by a
per-atom volume (`compute voronoi/atom`) before calling the result a stress;
quoting its output directly in GPa is wrong by a factor of the atomic volume.
(the user, 2026-08-20.)

### 1.15 Derived diagnostic columns must earn their place

Before adding a derived per-step or per-block output column, state in the
input header what it measures that the existing columns do not -- and verify
that claim on the probe by regressing the new column against the ones already
written. A column that is a deterministic function of an existing column
carries zero information: either drop it, or label it explicitly as a
convenience restatement so a later reader does not assume it means something.
(2026-08-05: `V_oct_ideal` / `V_tet_ideal` added to three runs to resolve
oct-vs-tet occupancy turned out to be exactly a^3/6 and a^3/24 of the a_eff
column already present, verified to 1e-5 over all 16256 rows -- four runs of
extra output with no occupancy information. Same failure class as the
2026-08-04 `metric volume` gotcha: a quantity assumed to discriminate
structure that is actually geometry. Merged 2026-08-25 from inbox
2026-08-05-1115.)

### 1.16 No `${}` inside `$(...)` formulas; variables in formulas are `v_name` (L44)

`${name}` is parse-time substitution; `$(...)` is an equal-style formula.
They must never nest. The parser does not substitute `${}` inside an
extracted formula, and a `$` is invalid formula syntax, so `$(ly/${L})`
dies with `ERROR: Invalid syntax in variable formula (src/variable.cpp)`.
Inside quoted strings the trap is doubled: the variable doc says verbatim
that "it is a mistake to enclose a variable formula in double quotes if it
contains variables preceded by $ signs ... the quotes prevent variable
substitution" -- `print` then evaluates the formula itself at run time and
hits the literal `${}`. Inside ANY formula, reference variables ONLY as
`v_name`; an index-style `-var` variable works if its string is numeric
(`$(ly/v_L)`).

Greps:

```
# hard gate — ${} nested inside $(...): must return nothing
grep -nE '\$\([^)]*\$\{' <input>
# read-and-confirm — quoted strings mixing ${} and $(...): every $() hit
# must survive print's own late evaluation (v_name references only)
grep -nE '"[^"]*\$\{[^"]*\$\([^)]*\)' <input>
```

(2026-08-24, ni-melting-point-eam probe 22719499: FAILED 18 s after a clean
NPT stage at the first `print` -- five `$(...${L}...)` instances across the
two thread-01 inputs. The existing checks verify every `${VAR}` is DEFINED
(§1.8) and that runtime quantities use `$(...)` (§1.1); neither constrains
WHERE `${}` may appear, so both passed. Merged 2026-08-25 from inbox
2026-08-25-1545.)

### 1.17 Deleted IDs must not stay referenced by thermo_style (L45)

`uncompute ID` / `unfix ID` remove the object, not its references. The
active `thermo_style custom` line is re-resolved at the next system init
(`run`, `minimize`, `write_data`, `write_restart`, `rerun`) -- a dangling
`c_ID`/`f_ID` there errors THEN, far from the deletion. Teardown order for
every staged input: unfix the stage's fixes, RESET `thermo_style` to a line
without the stage's computes, then `uncompute`. The lint mechanizes the
thermo case (join `&` continuations, then: deletion of a referenced ID +
a later init before a clearing `thermo_style` reset = fail). Fixes, dumps
and variables that consume `c_ID`/`f_ID` are the same class -- walk them
manually at every `uncompute`/`unfix`.

(2026-08-25, ni-melting-point-eam prepare probe attempt 2: `write_data`
died on stage-2 `thermo_style ... c_TEMP_HOT` after `uncompute TEMP_HOT`;
stages 1-2 clean. Second submission lost to the same input; all three
commands are individually correct, only the order is wrong. Merged
2026-08-25, designer+pilot session, no inbox round-trip -- lock was held.)

### 1.20 A log-parsing harvest must survive the command echo (L48)

LAMMPS writes each input command to the log verbatim BEFORE that command's
output, so the first regex match for a printed quantity is the command text,
`$(...)` unevaluated. Read-and-confirm, not a hard gate -- the harvest scripts
live outside the `.in`:

```
# every re.search / grep over a .log for a value that a `print` produced:
# take the first match that parses as the expected type, or anchor past the
# echo (e.g. search after the "Step " header, or use the LAST match).
grep -n 'print .*=' <input>.in      # each of these appears twice in the log
```

The loud failure is a `ValueError` on `float()`. The dangerous one is a command
whose text happens to parse -- a hardcoded literal in the command -- where the
harvest returns a plausible wrong number and nothing raises.

## 2. Rules from lessons.md

This section references the canonical entries in `../lessons.md`. The
checklist above operationalizes these; this section names them for
context when reading inputs.

- **L1** — `$(...)` for runtime quantities; `${...}` is parse-time only.
- **L2** — ASCII-only inputs (incl. comments).
- **L3** — Descriptive filenames; no quickstart-tutorial defaults.
- **L4** — MEAM library element list = parameter-file's index references.
- **L5** — `fix print` is not invoked during `minimize`.
- **L6** — `log <descriptive>.log` first; `-screen none` in srun.
- **L7** — `${POTDIR}` variable for shared potentials; one place to edit.
- **L8** — `pair_style meam` (no /c) for lammps/250722; check version.
- **L9** — `ftol` = global force 2-norm, scales √(3N); pick per-atom RMS target first.
- **L10** — `min_modify line quadratic` before `minimize` when `fix box/relax` is in play.
- **L12** — FIRE / quickmin incompatible with `fix box/relax`; use cg / hftn / sd.
- **L13** — Cubic-axis-aligned cell (x∥[100], y∥[010], z∥[001]) for Cij.
- **L18** — Output only what answers the current question; no full-menu defaults.
- **L19** — `fix print` format string: `$(...)` for runtime, `${...}` for static labels.
- **L20** — Descriptive-names rule applies to ALL outputs, not just `.data`.
- **L22** — Cell side ≥ 5× max cutoff for small-strain Cij work (stress numerics).
- **L23** — Diff local potential files against claimed OpenKIM entries before pinning citation.
- **L27** — No in-loop `thermo` doubling when a dedicated dump file exists (see §1.11).
- **L28** — `fix_modify ... format` unsupported on `fix ave/time`; accept default `%g` or post-process.
- **L29** — `fix ave/time` title1/title2 are literal; no `${}`/`$()` substitution in headers.
- **L30** — Standalone `print`: no bare `%` (printf-conversion trap); keep static or use `$()`/`${}` (see §1.12).
- **L31** — `%d`/`%i`/`%x` illegal inside `$(...)` (values are doubles) in both `print` and `fix print`; use `$(step)` or a float format (see §1.12). Corrects L30's discriminator.
- **L48** — LAMMPS echoes each command to the log before its output; a `.log` harvest must not trust a bare `re.search` (see §1.20).

Remaining placeholder slots (still lost between sessions):
**L11, L16** — see `../lessons.md` (shell-rule slots).

---

## 3. Standing conventions (not numbered as lessons)

These predate the walk but live here because they're consulted at write
time.

### Descriptive-naming vector: the `POTENTIAL_LABEL` variable convention

Set `variable POTENTIAL_LABEL string "<Label>-<Family>"` near the top of
the input (e.g., `"Pezold-EAM"`, `"KoShimLee-MEAM"`). Then every output
filename interpolates it:

```
log     Ni-fcc-${POTENTIAL_LABEL}-min.log
...
fix LOG_THERMO all print 1 "$(step) ..." file Ni-fcc-${POTENTIAL_LABEL}-relaxation-log.dat
print "..." file Ni-fcc-${POTENTIAL_LABEL}-a0-result.txt
write_data Ni-fcc-10x10x10-a0-min-${POTENTIAL_LABEL}.data nocoeff
dump FINAL_SNAPSHOT all custom 1 Ni-fcc-${POTENTIAL_LABEL}-final-snapshot.dump id type x y z c_PE_ATOM
```

Single point of change (the variable) propagates to every output. Makes
two-potential thread setups (Thread 01's pattern) much easier to
parameterize via sed.

### Exception to descriptive-naming: shell-script bookkeeping artifacts

`start_time.txt`, `end_time.txt`, and similar timestamps emitted from
the submit script (not from LAMMPS) can stay generic. They're
shell-script convention, scoped to one run dir, and the user's existing
example submit scripts do the same. The descriptive-names rule applies
to LAMMPS outputs and to artifacts that move between runs (mile-pebbles,
plot data). Pure within-run bookkeeping is exempt.

### Margin note on L5 (fix print during minimize)

A mid-debug snapshot of the walk diagnosed the no-output bug as cadence
mismatch (`fix print 50` vs. 4 minimize iterations → no row hit). The
resolved understanding (per CHECKPOINT.md end-of-walk analysis) is that
`fix print` is not invoked at minimize iterations *at all*, regardless
of cadence. If both diagnoses turn out partially right (e.g., fix print
fires at minimize entry/exit only, but not on intermediate iterations),
update L5 in `lessons.md` accordingly. Until then: use `thermo_style
custom` with equal-style variable columns for per-iteration printout
during minimize, not `fix print`.

### Input file structure (order)

1. `log <descriptive>.log` — must be the first non-comment directive.
2. Header comment block — author, date, project, thread, what this
   input does. ASCII only.
3. `# NEED TO SET:` line listing ALL CAPS placeholders if rendered from
   a skeleton (per `learnings.md` LAMMPS-specific section).
4. `units`, `boundary`, `atom_style` — `metal`, `p p p`, `atomic` per
   `preferences.md` defaults unless system demands otherwise.
5. Structure: `read_data` or `lattice` + `region` + `create_box` +
   `create_atoms` + `mass`. If `read_data`, the data file is itself
   subject to descriptive-naming.
6. `pair_style` + `pair_coeff` — full multi-file form for MEAM/ReaxFF;
   element list per L4.
7. Computes / thermo style / thermo cadence — `thermo_style custom step
   temp etotal fnorm fmax` as default, extend per system.
8. Fixes — note minimize compatibility per L5.
9. `minimize` (if applicable) — `min_style cg`, `etol 0.0`,
   `ftol 1e-3`, iter cap `800000` per `preferences.md` defaults.
10. `write_data <descriptive>.data` — explicit descriptive filename.
11. Optional `dump`, `print` for closing summaries (`print "a0 =
    $(lx/10.0)"` style).

### Post-minimize per-atom snapshot idiom

To capture one labeled snapshot of the final geometry after a
minimization, without running real dynamics:

```
compute     PE_ATOM all pe/atom
dump        FINAL_SNAPSHOT all custom 1 Ni-fcc-${POTENTIAL_LABEL}-final-snapshot.dump &
            id type x y z c_PE_ATOM
dump_modify FINAL_SNAPSHOT sort id first yes
run         0    # triggers one dump write at the current (post-minimize) state
undump      FINAL_SNAPSHOT
```

- `run 0` is the trick: it executes zero MD timesteps but still
  triggers all configured outputs (dumps, thermo) at the current state.
- `sort id first yes`: deterministic atom ordering across runs (useful
  for diff'ing snapshots between potentials).
- Output columns follow the L18 rule: only what answers the current
  question. For a 0K relaxation, that's `id type x y z c_PE_ATOM` —
  no per-atom stress, no virial.

### OVITO sanity check for bulk relaxations

For a defect-free bulk crystal post-minimization, `c_PE_ATOM` should
be uniform across atoms (within float noise). Open the
`final-snapshot.dump` in OVITO with a colormap on the energy column:
any visible structure = relaxation didn't find the symmetric ground
state (residual strain, broken-symmetry minimum, surface effects from
wrong PBC, etc.). Cheap and fast first check before reading the log.

### Multiline continuation

Do **not** use multiline `&` continuation. One command per line, full
length. (`learnings.md` LAMMPS-specific.)

### Placeholder tokens for sed-rendering

Bare ALL CAPS: `STRUCTURE`, `FUPPER`, `FLOWER`. Not `__STRUCTURE__`,
not `{STRUCTURE}`. (`learnings.md` LAMMPS-specific.)

---

## 4. Automation

`../templates/lint-lammps-input.sh` mechanizes §1.1–1.5 + 1.8 + 1.16 + 1.17 (thermo case)
(hard gate only; the quoted-string read-and-confirm grep stays manual). The
pilot runs it as part of pre-flight on every input. Manual review still
required for §1.4 (MEAM element index), §1.6 (log line position),
§1.7 (cadence sanity), §1.9 (version doc-check) — those are not purely
grep-able.
