# LLM-LAMMPS — Architecture (v0 draft, 2026-05-28)

> This is the design contract for LLM-LAMMPS, consolidated from the design
> conversation on 2026-05-27 and 2026-05-28. Read CHECKPOINT.md first for
> re-entry context. `brainstorm-notes.md` is the conversation log that
> produced this document; this file is what was decided, that document is
> how we got there.

## Quick read guide

- **Design contract:** this file (ARCHITECTURE.md).
- **Re-entry pointer:** CHECKPOINT.md.
- **Conversation history:** brainstorm-notes.md.
- **Where state lives** at runtime:
  - `~/Desktop/PROJECTS/<admin-project>/` — admin / institutional projects, owned by the user or by the email helper. LLM-LAMMPS reads, never writes.
  - `~/Desktop/SIMULATIONS/<sim-project>/` — simulation projects, owned by LLM-LAMMPS. Also holds legacy not-yet-ingested folders.
  - `canon/` — global pilot state (preferences, lessons, learnings, vocab, clusters, calibration, style guides, templates, **tool cards**). One canon shared across all projects; lives at `<REPO_ROOT>/canon/` as a **visible** folder (renamed from the former hidden `.lmps/` on 2026-06-01 — see §6).
  - `~/cluster-mounts/<cluster>/` — sshfs-mount of user's ptmp on each cluster.
- **Open items deferred to walk-through:** end of document.

## Table of contents

1. What it is (and isn't)
2. The five hard rules
3. Identity, ownership, and locations
4. The hierarchy: project → thread → run → simulation
5. Per-project files: project.md, thread.md, run.yaml
6. Global state (`canon/`)
7. The three-script pattern
8. The cluster bridge
9. Workflow: opening a project
10. Workflow: running a thread
11. Workflow: running a run
12. Iteration model: pre-flight / silent fix / logged closure
13. Closure and mile-pebbles
14. Archive prep
15. Open items (for walk-through and beyond)
16. End-to-end example (folder layout)
17. Concurrency model: pilot/designer modes, dashboard, inbox

---

## 1. What it is (and isn't)

LLM-LAMMPS is an **LLM-first co-thinker for the iterative, non-DAG process of finding things out with LAMMPS**. Its job is to compress the distance from "I have a question" to "I have a plot or a dead end I understood" by absorbing the syntactic mediation the user would otherwise have to do himself in LAMMPS / Python / bash / awk / OVITO / Jupyter.

It is explicitly **NOT**:

- An RDM (research data management) system.
- A workflow engine. Specifically rejects AiiDA-style and pyiron-as-workflow framings, and Snakemake/Nextflow-style DAG-first designs. Real science is non-DAG (false starts, "wait let me try X instead", reformulating the question); workflow tools force a DAG you don't have yet.
- An ontology project. Ontologies/vocabularies are used **where they pay off** (cross-project search, archive time, downstream interop with pyiron), not exhaustively, not upfront.

What it earns its keep by:

1. Reducing time from idea → plot.
2. Letting the user re-enter a project fast after a gap.
3. Letting a PhD student take over a project the user leaves.
4. Making the eventual archive/publish step nearly free (vocabulary alignment as a quiet byproduct).
5. Capturing the *why* in a form both the user and the pilot can use later.

A feature for this tool earns its keep if it touches (1)–(3); (4) and (5) are nice but not sufficient on their own.

## 2. The five hard rules

These are non-negotiable. They also live in `canon/learnings.md` and apply session-to-session.

1. **The LLM owns the write channel.** the user never types into project files — not project.md, not thread.md, not scripts, not anything. He speaks in chat; the pilot transcribes. He can read files anytime. Reactions like "atoms overlapped, try Anderson-Cottrell" get woven into thread.md by the pilot, not pasted in by the user.
2. **Descriptive file names always.** No `dump.out`, no `run1/`, no `restart.data`. Every file gets a descriptive name. Pilot picks; the user shouldn't have to nag.
3. **Cluster access is gated.** Sbatch is strict-A always: pilot prepares, the user runs in his terminal. Cluster *file operations* use the mount, with read-free / write-requires-the user-OK. The user never has to type a file into a thread.md, but he *does* execute every command that touches cluster state.
4. **Brainstorm mode is the default for new design questions.** Don't push for scoping or "what's v0?" until the user signals.
5. **Plain files only.** YAML, markdown, JSON, parquet. No databases. LLM-agnostic substrate — any LLM (Claude, GPT, local) can read/write the same files. Cowork is the user's chosen driver, not a dependency. **Corollary:** ephemeral surfaces (Cowork task list, chat scratchpad, `/outputs/`) are not storage. Any lesson, decision, or note worth keeping lands in a plain file *the moment it surfaces*. Don't park substantive content for "later drain" — task lists do not persist between sessions. (Incident: 2026-05-29.)

## 3. Identity, ownership, and locations

### Canonical ID

Each project (admin or sim) carries a canonical `id` (slug form, e.g. `cuAl-disloc`, `sfb1394-a02`). This is the contract shared with the email-helper sister project: both tools use the same `id` namespace. References between tools are by `id`; physical paths are observations.

### Ownership boundary

- `~/Desktop/PROJECTS/` is touched by **The user + the email helper**. Holds admin / institutional projects (grants, papers, slides, presentations). LLM-LAMMPS reads (to follow `parent` pointers from sim-projects up to admin context); LLM-LAMMPS never writes here.
- `~/Desktop/SIMULATIONS/` is touched by **LLM-LAMMPS only**. Holds sim-projects. Folders without a `project.md` are legacy / not-yet-ingested — LLM-LAMMPS doesn't touch them until you ask. "Ingestion" stamps a `project.md` in place; nothing moves, nothing renames.
- `canon/` is touched by **LLM-LAMMPS only**.
- `~/cluster-mounts/<cluster>/` is touched by **LLM-LAMMPS** (with the read-free / write-with-OK rule) plus the cluster itself (which writes as the jobs run).

### Lineage fields

- `parent: <admin-project-id>` — optional, assignable later. A sim-project usually has a grant-funded admin parent, but a personal exploration / methods scratch / debug-LAMMPS sandbox may not. Parentless is fine.
- `follows_from: [<sim-project-id>...]` — distinct from `parent`. This is sim-project-to-sim-project lineage (a forked sim-project carries both: same admin parent, plus its sim-project predecessor in `follows_from`).
- `succeeded_by: <sim-project-id>` + prose note — the reverse pointer on the predecessor sim-project (set when a fork happens).

### Locations map

Each sim-project carries a `locations:` map tying paths across machines. Identity rides on `id`; folder names may diverge across machines, that's fine.

```yaml
locations:
  mac:projects:    ~/Desktop/PROJECTS/<GRANT>/<SUBPROJECT>/        # parent admin (read-only)
  mac:simulations: ~/Desktop/SIMULATIONS/cuAl-disloc/     # sim-project home
  cluster:cmmg:    /cmmc/ptmp/<CLUSTER_USER>/cuAl-disloc/        # cluster-side path
  cluster:cmmg:mount: ~/cluster-mounts/cmmg/cuAl-disloc/  # mount-translated local path
```

The pilot can translate cluster-side paths to mount-local paths via `clusters.yaml`'s `mount.remote` / `mount.local` pair.

## 4. The hierarchy: project → thread → run → simulation

```
project           ~/Desktop/SIMULATIONS/<sim-project>/
  └── thread      <NN_step-descriptive>/                  one question / one step
        └── run   <NN_run-descriptive>/                   one sbatch invocation
              └── simulation <descriptive-sim-name>/      one LAMMPS execution
```

- A **project** answers a scientific question with a definite endpoint (closes when answered, or forked if the question drifts significantly).
- A **thread** is one question-scoped step inside the project. Forks happen by closing the current and opening a new one with `parent_thread:` pointing at the branching moment. Failed attempts of the *same* question become lazy `attempt-*/` subfolders inside the thread folder (don't appear unless retries happen). Analysis is continuation of the simulation arc; same project, later threads.
- A **run** is one `sbatch` invocation. The shell script's logic can be arbitrarily complex — a sweep, a restart chain, an equilibrate-then-production sequence.
- A **simulation** is one LAMMPS execution inside a run. Each simulation gets its own descriptive sub-folder.

### Folder naming

- **Rule:** CAPITALS for directory names, **preserve chemical element
  typography** (Ni not NI, Al not AL, Cu not CU, etc.). The `id` field
  in frontmatter stays lowercase-kebab (e.g., `ni-a0-cij-eam-meam`);
  directory names use the CAPS form
  (`Ni-A0-CIJ-EAM-MEAM/`). (Established 2026-05-29.)
- Threads: `NN_<DESCRIPTIVE-STEP-NAME>/` (e.g. `01_LATTICE-CONSTANT-AT-0K/`,
  `02_ELASTIC-CONSTANTS-AT-0K/`).
- Runs: `NN_<DESCRIPTIVE-RUN-NAME>/` (e.g. `01_MIN-EAM-PEZOLD/`) or
  `<NAME-ENCODING-PARAMETERS>.tau<value>/` (the user's existing style).
  Both work.
- Simulations: `<DESCRIPTIVE-SIM-NAME>/` (e.g. `T-300K_NVT-10ns/`).
- Helper scripts (project-scoped or thread-scoped) sit at their
  respective levels and are referenced relatively.
- **Note on case-insensitive filesystems:** macOS APFS/HFS+ is
  case-insensitive by default; most cluster filesystems are
  case-sensitive. If two names ever differ only by case, the mount
  would alias them on Mac but not on cluster. Avoid case-only
  distinctions across the project tree.

## 5. Per-project files

### project.md — project root

One file per sim-project, living at `~/Desktop/SIMULATIONS/<sim-project>/project.md`. Markdown with YAML frontmatter. Always loaded into the pilot's context when working in this project. Lives as a *page*, not a chronicle — when the body grows past its budget, content factors out into thread.md files or a "lessons learned" subsection.

**Frontmatter:**

```yaml
---
id: cuAl-disloc
name: Cu/Al edge dislocation Peierls stress study
parent: sfb1394-a02                          # admin project id (optional, assignable later)
follows_from: []                             # predecessor sim-project ids
succeeded_by: null                           # set if this project gets forked
owner: erik                                  # always the user (PI)
collaborators: []                            # named others (may be empty)
operator: erik                               # current keyboard-and-submit person
started: 2026-05-28
funding: [<GRANT>-<SUBPROJECT>]                       # grant strings (verbatim for acknowledgements)
sharing: pre-publication                     # / publishable / industry-confidential
primary_cluster: cmmg                        # default submit target
locations:
  mac:projects:        ~/Desktop/PROJECTS/<GRANT>/<SUBPROJECT>/
  mac:simulations:     ~/Desktop/SIMULATIONS/cuAl-disloc/
  cluster:cmmg:        /cmmc/ptmp/<CLUSTER_USER>/cuAl-disloc/
vocab:                                       # lazy; fills in as discussion crystallizes
  material_system: Cu-Al alloy (1.2% Al in Cu fcc)
  potential: EAM Mishin
  simulation_engine: LAMMPS
  simulation_type: NVT MD with Nosé-Hoover   # → MatCore: mode=Equilibrium dynamics,
                                             #   algorithm=Velocity Verlet, ensemble=NVT,
                                             #   method=Nosé-Hoover
  primary_observable: Peierls stress
companion_assets:
  papers: []                                 # paper-project ids in email-helper
  slides: []
  openbis_entry: null
  email_helper_id: cuAl-disloc-helper        # same canonical id by default
---
```

**Body:**

- *The why* — current best statement of the scientific question (always in context). When the why drifts significantly, fork a new project, don't update in place. (See §7 of brainstorm-notes for the fork-conversation pattern.)
- *Current best statement of the approach* — what we're trying to do scientifically.
- *Open scientific questions* — short list of what's still unanswered at the project level.
- *Project-level scientific lessons* — observations specific to *this* project (vs. global lessons in `canon/lessons.md`). E.g. "we ruled out ADP after lattice-constant problems at this composition."
- *Rough sketch / what to read first on re-entry* — pilot-maintained; the page the user reads after a week away.
- *How the question has evolved* — optional subsection; appended-to as the project's framing matures.

### thread.md — each step folder

One per thread (= per step folder), at `<NN_step>/thread.md`. Markdown with YAML frontmatter. The *live* level (step level when no attempts; attempt level when there are attempts).

**Frontmatter:**

```yaml
---
thread_id: 02_create-dislocation
project_id: cuAl-disloc                      # sim-project id (admin is derivable)
question: Insert edge dislocation into the relaxed Cu block
status: succeeded                            # active / paused / succeeded / failed / abandoned
                                             # — mostly derived (mtime, all-attempts-closed,
                                             #   pilot prompt → the user confirm)
parent_thread: null                          # forked from? null = root
branched_to: []                              # forks spawned from this thread's closure
consumes:                                    # general "builds on prior thread" pointer
  - thread: 01_create-crystal                # can point at success mile-pebble (forward
    mile_pebble: Cu-fcc-10x10x10-relaxed.data #   dependency) OR failed-thread verdict
                                             #   (lesson dependency)
opened: 2026-05-29
closed: 2026-05-29
mile_pebble:
  name: Cu-edge-dislocation-Anderson-Cottrell.data
  type: lammps-data-file
  meaning: |
    Cu fcc block with single edge dislocation inserted via Anderson-Cottrell
    scheme, ready for relaxation.
  produced_by_run: 02_anderson-cottrell-insertion/
  paths:
    mac: ~/Desktop/SIMULATIONS/cuAl-disloc/02_create-dislocation/02_anderson-cottrell-insertion/Cu-edge-dislocation-Anderson-Cottrell.data
    cluster:cmmg: /cmmc/ptmp/<CLUSTER_USER>/cuAl-disloc/02_create-dislocation/02_anderson-cottrell-insertion/Cu-edge-dislocation-Anderson-Cottrell.data
  backup_status: pulled-to-mac-compressed
verdict: |
  Anderson-Cottrell with explicit core relaxation gave clean dislocation
  (min nn distance > 2.3 Å, core energy 0.45 eV/Å). Replaces failed
  Volterra attempt (see attempt-1-volterra/).
---
```

**Body:**

Narrative log of what was done, why, and how it went. Written *by the pilot*, woven from chat. Not a shell transcript. Contains:

- Commands (written by pilot, for traceability and replay; runnability preserved)
- Job ids, walltimes, output paths
- The user's in-chat reactions, transcribed
- Discussion outcomes for layer-3 situations
- Closure pointer back to the frontmatter mile-pebble / verdict

### run.yaml — each run folder

One per run (= one sbatch), at `<NN_run>/run.yaml`. Pure YAML, no markdown. Mostly auto-fillable from artifacts.

```yaml
# Identity & containment
run_id: 01_temperature-sweep-NVT-100-500K
thread_id: 03_equilibration
project_id: cuAl-disloc

# Cluster context
cluster: cmmg
partition: p.cmmg
queue_job_id: 1234567
submit_script: submit-temperature-sweep.slurm
template_input: input-template-NVT.lammps    # null if single-sim, no template
driver_script: ../nvtshear_dislo.bsh         # null if direct sbatch, no outer driver

# Resources
n_cores: 64
gpu: null
walltime_requested: 12h
walltime_estimated: 9h                       # from calibration at submit
walltime_used: 8h47m                         # filled at close

# Timeline
submitted_at: 2026-05-28T14:32
started_at:   2026-05-28T14:38
finished_at:  2026-05-28T23:25

# Outcome (lightweight — real story lives in thread.md)
status: completed                            # submitted/running/completed/failed/partial
outcome: succeeded                           # succeeded / failed-scientifically / partial

# Paths
paths:
  mac:          ~/Desktop/SIMULATIONS/cuAl-disloc/03_equilibration/01_temperature-sweep-NVT-100-500K/
  cluster:cmmg: /cmmc/ptmp/<CLUSTER_USER>/cuAl-disloc/03_equilibration/01_temperature-sweep-NVT-100-500K/

# Per-simulation list
simulations:
  - sim_id: T-100K_NVT-10ns
    input_file: input-NVT-T100K.lammps
    substitutions: { TEMPERATURE_K: 100 }
    n_atoms: 4000
    n_steps: 10000000
    lammps_version: lammps/250722
    ns_per_day: 28.4
    time_per_step_per_atom_per_core: 1.41e-7  # seconds; feeds cluster-calibration.yaml
    status: succeeded
    outputs:
      - log.lammps
      - Cu-equilibrated-NVT-T100K.data
      - dump-thermo-T100K.dat
    outputs_kept_on_mac:
      - Cu-equilibrated-NVT-T100K.data
      - dump-thermo-T100K.dat
    notes: null
  # ... T-200K, T-300K, T-400K, T-500K
```

### `potential` block schema (per-simulation, inside `simulations[].potential`)

Formalized from the 2026-05-29 Ni-baseline walk (see `canon/lessons.md`
L4, L7, L8, L23). All fields optional except `file` / `files` (one of)
and either `citation_doi` OR `source_provenance` (provenance must be
identifiable somehow).

```yaml
potential:
  # File reference — use file: for single-file potentials, files: for multi-file
  file: ni_h_rcut4.90_rcut2.eam.alloy            # EAM single setfl file
  # OR (mutually exclusive with `file:`):
  files:                                          # MEAM, ReaxFF, etc.
    library:   NiH_KoShimLee_library.meam        # extractable elements list
    parameter: NiH_KoShimLee.meam                # the actual parametrization

  # Identity / lineage
  family: EAM                                    # EAM | MEAM | MEAM-2NN | ReaxFF | Tersoff | LJ | ...
  parametrization: "von Pezold et al. (2011)"    # short-form attribution
  lineage: "Angelo-Moody-Baskes (1995/97) → Pezold (2011)"  # optional

  # Citation
  citation_doi: 10.1016/j.actamat.2011.01.037
  citation_short: "von Pezold, Lymperakis & Neugebauer, Acta Mater. 59, 2969 (2011)"
  citation_title: "Hydrogen-enhanced local plasticity at dilute bulk H concentrations..."

  # OpenKIM identity — preferred canonical pointer per L23 workflow
  openkim_short_id: MO_535504325462              # version-independent
  openkim_extended_id: EAM_..._..._004           # version-pinned, byte-verified
  openkim_id: null                               # set to null explicitly if file is NOT in KIM

  # Provenance (always present — either via openkim_*_id or this)
  source_provenance: "received from Tehranchi; pre-Tehranchi-Curtin (2017) Pezold parametrization"

  # Physical scope
  cutoff: 5.65                                   # Å, primary cutoff
  cutoff_per_pair:                               # for multi-species potentials
    Ni-Ni: 4.90
    Ni-H:  4.92
  fit_targets: "H-H interactions, local hydride formation at dislocations"

  # File fingerprint — for diff verification per L23
  file_fingerprint:                              # extracted from file header
    nrho: 1000
    drho: 0.01300723
    nr: 1000
    dr: 0.005678
    rcut_header: 5.65
```

**Field rules:**

- **`file` xor `files:`** — exactly one of these present. Use `files:`
  with named sub-keys whenever the format requires more than one
  physical file (MEAM: library + parameter; ReaxFF: param + optional
  aux files like control or table files).
- **`openkim_*` is the preferred canonical pointer** when the
  potential is archived in OpenKIM. `openkim_short_id` is the
  version-independent identity; `openkim_extended_id` adds the
  version pin and SHOULD be byte-verified per L23 workflow before
  recording (otherwise it falsely claims byte-level reproducibility).
- **`openkim_id: null`** is the explicit "not in KIM" marker. Don't
  omit the field — explicit-null signals "checked and not in KIM",
  vs. omission which is ambiguous.
- **`file_fingerprint`** captures the file's identifying numerics
  (the line-2 setfl header for EAM; equivalent for other formats).
  Catches silent file substitutions.
- **`cutoff_per_pair`** only when the potential has different cutoffs
  for different species pairs (common in EAM Ni-H, ReaxFF, etc.).

### Design notes (run.yaml)

- `outputs` vs `outputs_kept_on_mac`: explicitly separates "what was produced on cluster" from "what was curated back to Mac". Big trajectories stay on cluster.
- `time_per_step_per_atom_per_core` per sim feeds `canon/cluster-calibration.yaml` on close — the rolling estimate that powers walltime prediction for future submits.
- `walltime_estimated` survives the run so calibration accuracy can be measured.
- No `iterations_to_success` tally — mechanical iteration is noise; patterns surface in `canon/learnings.md`.

## 6. Global state (`canon/`)

All written exclusively by the pilot. All readable by the user anytime. Lives on Mac, shared across all projects.

> **Location (decided 2026-06-01; path made repo-relative 2026-07-28):** canon lives at `<REPO_ROOT>/canon/` as a **visible** folder. `<REPO_ROOT>` means *the root of this framework repo, resolved from wherever it is checked out* — never a hardcoded absolute path; it was `~/Desktop/DEVEL/LLM-LAMMPS/` in 2026-05/06 and the tree has since moved. It was formerly the hidden `.lmps/` dotfolder with a planned promotion to `~/.lmps/` (home); that plan was dropped — hiding the most-read-at-runtime material fought hard rule 1's "the user reads files anytime", and a home-global path bought nothing with a single machine. The design/meta docs (this file, SESSIONS.md, brainstorm-notes.md) stay at the repo top level; the design-vs-canon boundary is now a visible sub-folder split, not hidden-vs-visible. The sibling `examples/` dump stays at `<REPO_ROOT>/examples/`.

```
canon/
├── preferences.md            # scientific preferences (units, go-to potentials, plot defaults)
├── lessons.md                # project-agnostic scientific findings
├── learnings.md              # pilot self-improvement (source of truth)
├── vocabulary.yaml           # local ↔ pyiron ↔ EMMO ↔ MatCore mappings (lazy)
├── clusters.yaml             # per-cluster knowledge
├── cluster-calibration.yaml  # runtime estimation rolling table
├── examples-catalog.md       # one-line index of files in the examples/ dump
├── style/
│   ├── lammps.md             # LAMMPS input style
│   ├── shell.md              # shell + slurm style
│   ├── python.md             # Python analysis/orchestration style
│   └── ovito.md              # OVITO scripting style
├── templates/
│   ├── submit-cmmg.slurm.skel
│   └── ...                   # one per cluster as we encounter them
└── tools/                    # tool registry — CARDS ONLY, never tool code
    ├── tools-catalog.md      # one-line index; pinned in session-start state
    ├── tool-card.skel        # card template
    └── <id>.card.yaml        # one plain-file contract per tool

# Sibling dump (NOT inside canon/; bulk artifacts, low curation cost):
LLM-LAMMPS/examples/            # flat folder of reference artifacts
```

### preferences.md, lessons.md, learnings.md

All three are living markdown. Additive — new entries appear; old ones get edited or pruned by the pilot as warranted. Pilot proposes additions ("you always use metal units for fcc metals — add to preferences?"); the user confirms.

- **preferences** = your defaults (unit styles, go-to potentials per material, canonical recipes, plot defaults).
- **lessons** = observed scientific gotchas, project-agnostic ("ADP for Cu/Al is bad at >15% Al"; "Volterra fails for high-Schmid orientations").
- **learnings** = pilot behavioral rules. Canonical; Anthropic-side memory mirrors this file. Examples:
  - Use descriptive file names; no `dump.out`
  - Look up LAMMPS docs of the version in use before writing syntax; don't guess
  - Don't ask about deadlines unprompted (stresses the user)
  - Three-layer iteration model (pre-flight / silent mechanical / logged scientific)
  - When fail-late or at-specific-parameter, treat as scientific (layer 3), not mechanical (layer 2)

### vocabulary.yaml

Lazy mapping. v0 minimum: five fields.

```yaml
material_system:
  local: material_system
  pyiron: material
  emmo: ChemicalComposition          # placeholder IRI; verify at archive
  matcore: material                  # decomposes: phase / description /
                                     # constituent[species,concentration] /
                                     # microstructure

potential:
  local: potential
  pyiron: interatomic_potential
  emmo: InteratomicPotential
  matcore: particle-interactions     # model-type (free), bonding-type CV,
                                     # theory-level CV, source.reference,
                                     # source.doi, OpenKIM ID preferred

simulation_engine:
  local: simulation_engine
  pyiron: ~                          # class-based, no single field
  emmo: SimulationEngine
  matcore: software.name + software.version

simulation_type:
  local: simulation_type
  pyiron: job_type
  emmo: MolecularDynamicsSimulation
  matcore:                           # MatCore decomposes into four orthogonal fields:
    mode: computation.mode           # Static / Minimization / Equilibrium /
                                     #   Nonequilibrium / Free energy
    algorithm: computation.algorithm # FIRE / Velocity Verlet / Leap frog / ...
    ensemble: thermodynamic-constraint.type  # NVE / NVT / NPT / ...
    ensemble_method: thermodynamic-constraint.method  # Nosé-Hoover / Berendsen / ...
  notes: |
    Domain operations (dislocation insertion, shear deformation, NEB) don't have
    MatCore CV entries — they go into computation.initialization or
    thermodynamic-constraint.description as free text.

primary_observable:
  local: primary_observable
  pyiron: output_quantity
  emmo: PhysicalQuantity
  matcore: derived-property          # SEPARATE linked document (MatCore-Der ext).
                                     # CV is electronic-structure biased; typical
                                     # MD observables (lattice constant, elastic
                                     # constants, GSF, dislocation core energy)
                                     # fall to description free text.
```

EMMO IRIs are placeholders — verify against current EMMO/NFDI-MatWerk release at archive/publish time when it actually matters. Grow the file lazily as the pilot encounters new fields worth aligning.

### clusters.yaml

Per-cluster knowledge. v0 covers cmmg in detail; raven/viper/NHR-Erlangen fill in opportunistically.

```yaml
clusters:
  cmmg:
    aliases: [cmti]                    # cmfe partitions also use cmti hardware
    ssh:
      user: <CLUSTER_USER>
      host: <CLUSTER_HOST>
    mount:
      local:  ~/cluster-mounts/cmmg/
      remote: /cmmc/ptmp/<CLUSTER_USER>/      # user's ptmp only; nothing higher
    paths:
      ptmp:        /cmmc/ptmp/<CLUSTER_USER>
      potentials:  /cmmc/ptmp/<CLUSTER_USER>/POTENTIALS   # inside mount; pilot can access
      home:        /home/<CLUSTER_USER>                    # reference-only
    queue: slurm
    gpu: false
    partitions:
      - { name: p.cmmg, scope: ">1 node" }
      - { name: s.cmmg, scope: "≤1 node" }
      - { name: p.cmfe, scope: ">1 node, cmti hardware" }
      - { name: s.cmfe, scope: "≤1 node, cmti hardware" }
    modules:
      lammps:
        - lammps/241119
        - lammps/250722
    sbatch_defaults:
      # get-user-env REMOVED 2026-08-02 (this Slurm build rejects the
      # argument form). mail-type cut back to the backstop set 2026-08-26:
      # BEGIN/END are sent by the notify helper, with a body.
      hint: nomultithread
      mail-type: FAIL,TIME_LIMIT
      mail-user: <NOTIFY_EMAIL>
      output: "%x.out"
      error: "%x.err"
    notify:
      helper: /cmmc/ptmp/<CLUSTER_USER>/BIN/slurm-notify.sh
      source_of_truth: canon/templates/slurm-notify.sh
    occasional_overrides:
      reservation: The user                # only when urgent; not standard
    docs_url: "https://docs.mpcdf.mpg.de/doc/computing/clusters/systems/Sustainable_Materials.html"
    downtimes:
      pattern: "~every 4 months"
      typical_duration: 1d
    quirks: ""                         # empty for now; accumulates over time

  raven: { ... }                       # MPCDF; fortnightly downtimes; CPU+GPU
  viper: { ... }                       # MPCDF; fortnightly downtimes; GPU only
  nhr_erlangen: { ... }                # stability tbd
```

### cluster-calibration.yaml

Rolling estimate table keyed by `(cluster, potential_family, sim_type)`. Updated from per-run actuals as runs complete (rolling median + outlier rejection). Used at submit time to estimate walltime, which the pilot proposes and the user confirms.

```yaml
cmmg:
  EAM:
    equilibrium_NVT:
      time_per_step_per_atom_per_core: 1.4e-7   # seconds, median
      valid_range: { min_atoms_per_core: 50 }    # only count runs in this regime
      n_samples: 12
    minimization_FIRE: { ... }
  MEAM: { ... }
  ACE:  { ... }
raven: { ... }
```

### style/

Style guides per artifact type. Started near-empty; grows from observation and the user's confirmations.

**lammps.md** — initial content drawn from the user's existing examples:
- Date+author header (`# erik, <full-timestamp>`)
- "NEED TO SET STRESS, STRUCTURE, FUPPER, FLOWER" — explicit placeholder declaration in header comment (the skeleton declares what tokens it expects; pilot uses this for layer-1 pre-flight)
- Bare ALL CAPS placeholders for sed (`STRUCTURE`, not `__STRUCTURE__` or `{STRUCTURE}`)
- Never use multiline / line-continuation `&` symbols
- Always look up the docs of the LAMMPS version in use; never guess syntax
- Variables + computes pattern for atom-layer regions (regions → groups → fixes)
- Descriptive output file names (no `dump.out`)

**shell.md** — initial content:
- `#<author>, <full-timestamp>` header
- `set -euo pipefail` at top
- `module purge; module load lammps/<version>` before any LAMMPS use
- `LMP_BIN="${LMP_BIN:-lmp}"` env override pattern
- `cd "$SLURM_SUBMIT_DIR"`
- Pre-run existence check (`if [[ ! -f "$infile" || ! -f "$structure" ]]; then exit 1`)
- Two patterns: (A) outer driver creates per-parameter dirs, each dir is slurm submit dir; (B) single sbatch creates a sim sub-dir from inside the submit script
- File suffixes: `.bsh` for drivers, `.sh.skel` for submit skeletons, `.in.skel` for input skeletons
- Multi-substitution sed with `-e` flags; awk for arithmetic if not using Python driver
- Helper scripts (`lmps_shear_zx.awk` / `.py`) referenced by relative path
- `--reservation` flag only when the user says "urgent"

**python.md** — to accrue. Bias toward: pathlib, subprocess.run with check=True, f-strings, numpy/pandas/matplotlib defaults, integration with OVITO Python.

**ovito.md** — to accrue. OVITO pipeline pattern, common modifiers.

### templates/

Per-cluster submit skeletons drawn from observed-style + clusters.yaml defaults. The pilot uses these as starting points; per-run customization happens at write-time.

### examples-catalog.md + `LLM-LAMMPS/examples/` (the non-prescriptive layer)

A third layer alongside `style/` (mandatory rules) and `templates/` (executable mechanizers). Distinct in *role*: examples are **reference, not policy**.

- **`LLM-LAMMPS/examples/`** — flat dump-all folder for working artifacts: LAMMPS input fragments, gnuplot recipes, submit-script archetypes, closed-thread exemplars, OVITO snippets, anything the user wants the pilot to be able to point at later. The user says "add this to examples" or "save this thread's input as an example"; pilot copies it in. Flat (no subfolders) by design — low friction to dump, the catalog handles grouping.
- **`canon/examples-catalog.md`** — small markdown index. One line per file: filename + one-sentence description of what it demonstrates + provenance (date, source project). Pinned in session-start state so the pilot knows what's available; the example files themselves are read only when the user points at them.

**Addressing convention.** the user points by filename: "follow `examples/Ni-Cij-EAM.in` for the Cij setup". Pilot pulls that file. The catalog exists for when the filename has slipped the user's memory ("the Cij example with EAM") — pilot finds it in the catalog by description.

**Cataloging cadence.** On-demand only. The user says "recatalog examples"; pilot scans `examples/` and rewrites `examples-catalog.md`. Not auto-refreshed — examples can accumulate uncatalogued and that's fine. The catalog may lag the dump; that's the cost of a low-friction dump-all, and the user accepts it.

**Non-prescriptive rule.** Pilot does NOT treat examples as "the way to do it." Only consulted when the user explicitly points at one. The default source of normative behavior remains `style/` and `learnings.md`. If an example contains a pattern good enough to be normative, it gets promoted into `style/<x>.md` as a rule — not left to be picked up implicitly from the example.

### tools/ — the tool registry (added 2026-06-01)

External programs and promoted-internal utilities the pilot invokes instead of hand-rolling work. Two kinds of tool, **one abstraction**:

- **External tools** the user already owns — installed in `~/bin/`, their own GitHub repos, still under development. E.g. LEGO (`github.com/<GITHUB_USER>/LEGO`), LEGO-TOOLS, dcreator (`github.com/<GITHUB_USER>/dcreator`).
- **Emergent/internal tools** — operations the pilot hand-rolls repeatedly (file checks, log parsing, curated mirrors, …). When the same operation recurs **3+ times**, it gets promoted to a real, tested, documented tool (see the promotion trigger in `canon/learnings.md`).

**The tool card.** Both kinds are described to the pilot by one plain-file contract — a *tool card* (`canon/tools/<id>.card.yaml`, template `tool-card.skel`), exactly parallel in role to `style/` and `examples-catalog.md`. A card is the contract the pilot reads to call the tool correctly: id, purpose, owner, upstream repo, per-platform invocation (`exec.mac` / `exec.cluster`), `run_where` routing, I/O contract, `version` + `last_verified` stamp, and accrued gotchas. The pilot reads the **card**, never the tool's source. `canon/tools/tools-catalog.md` is the one-line index, pinned in session-start state.

**Canon holds only cards — never tool code.** This is the load-bearing rule. The framework stays a pure plain-file, LLM-agnostic substrate (hard rule 5); the moment tested/parallel/C code lives inside canon it becomes software that must be built and deployed on two machines. So promoted-internal tools graduate into their own small repo(s), deployed to `~/bin/` on Mac **and** the cluster — the same shape as the external tools. Canon carries the card; the repo carries the code, the tests, and the docs.

**Routing — Mac vs cluster.** The card's `run_where` is `mac` | `cluster` | `large-data->cluster`, and the pilot applies it. Large-data tools (dcreator, lego on real structures/trajectories) are `large-data->cluster`: never run on the Mac. They ride the existing §8 cluster bridge — read-free inspect, write-with-OK for outputs, strict-A for any `sbatch`. No new permission machinery; tools are just CLIs invoked through the bridge that's already there.

**Version drift.** External tools keep evolving, so a card carries `last_verified: <date> against version X`. Cards don't reproduce the tool's manual — they capture the contract the pilot needs and point at `--help`. When a card looks stale, the pilot re-probes (`tool --version` / `--help`) and re-stamps. Gotchas accrue on the card like `lessons.md` entries.

**Deferred:** MCP-wrapping of tools — against the lazy ethos; CLIs through the bridge are enough. Revisit only if a tool genuinely needs structured request/response the shell can't carry.

### local/ — the identity overlay (added 2026-07-28, gitignored)

This repo is public and **scrubbed**: cluster usernames, hostnames, notification addresses and Mac home paths appear only as placeholders (`<CLUSTER_USER>`, `<CLUSTER_HOST>`, `<NOTIFY_EMAIL>`, `<MAC_USER>`, `<DEVEL_ROOT>`, `<REPO_ROOT>`). The real values live in `canon/local/`, which is `.gitignore`d; `canon/local.example/` is the committed template.

```
canon/local/                    # gitignored — never committed
├── local.yaml                  # machine map (M5/M2/M1/mini) + local roots
└── clusters.local.yaml         # real ssh user/host/scratch per cluster + notify email
canon/local.example/            # committed template + setup and sync instructions
```

**Split of duty.** `canon/clusters.yaml` keeps the *structure* — partitions, modules, sshfs options, scratch policy, the lessons baked into them. `canon/local/clusters.local.yaml` supplies only the *substitutions*. The pilot reads both and resolves placeholders before writing any submit script, sshfs command or path into a project file. Nothing about how the cluster works needs to leave the public file, and nothing identifying needs to enter it.

**Machine awareness.** `local.yaml`'s `machines:` map lets the pilot answer "which Mac am I on?" from `hostname` before assuming a path resolves. `has_simulations: false` on the travel laptop is what stops a pilot from proposing a mirror onto a machine that must stay wipeable.

**The overlay does not replace asking.** `default_simulation_root` is the default the ritual *offers*; step 2 still asks the user for the simulation folder every session (§17.4).

**Guard.** `canon/templates/lint-no-identity.py` fails if any tracked file contains a value from `canon/local/` or matches a generic identity pattern (email, `/Users/<name>`, `ssh user@host`, MPCDF hostname, real scratch path). Run it before every push.

**Two-machine sync.** `canon/local/` is a few kB of text that must agree on M5 and M2. Preferred mechanism: a **private git repo** cloned into `canon/local/` — consistent with "code: GitHub is authoritative", and invisible to the parent repo because the path is gitignored. Alternative: an iCloud Drive folder symlinked in (config-sized, so it does not violate "keep research data out of iCloud"), at the cost of no history and occasional staleness. See `canon/local.example/README.md`.

### Relationship to the host LLM's own memory (revised 2026-07-28)

Earlier versions of this framework wrote durable behavioural rules into a host-provided "auto-memory" store (`MEMORY.md` + `feedback_*.md` files) *in addition to* canon. That layer is **retired**. All ~10 references have been repointed at `canon/learnings.md`.

Reasons, in order of weight:

1. **Hard rule 5.** A host-owned memory store is not a plain file in this repo. It cannot be diffed, reviewed, linted or carried to another LLM — the exact dependency hard rule 5 exists to prevent.
2. **It duplicated canon.** Every auto-memory entry had a canon twin, so the two could drift, and the drift is invisible until a session follows the wrong copy.
3. **The host's memory changed shape.** Cowork's persistent memory is now a *personal* store, shared across all of the user's sessions and surfaces — not a per-project one. Framework rules do not belong in it.

**The boundary, stated once:** anything that is true about *the framework* or *a project* goes in canon or in the project's own files. The host's personal memory may hold cross-cutting facts about the user (his conventions, his clusters, how he likes output) and the framework neither writes to it nor depends on it. A session that has such memory will read it and will be slightly better calibrated; a session that does not must behave identically after reading canon. **Canon is sufficient on its own — that is the test.**

## 7. The three-script pattern

Multi-run threads (sweeps, parameter studies) use a three-script pattern. The driver lives at thread level; per-run sub-folders carry the instantiated scripts plus outputs.

```
<NN_thread>/
  thread.md
  <driver>.bsh           or  <driver>.py       # outer orchestration; runs on login node
  <submit>.sh.skel                              # slurm batch script template
  <input>.in.skel                               # LAMMPS input template
  <helpers>.awk          or  <helpers>.py       # reusable transformations (e.g. shear awk)
  <NN_run-param1>/
    <submit>.sh.<param1>                        # instantiated
    <input>.in.<param1>                         # instantiated
    <structure-transformed>.lmps
    run.yaml
    log.lammps, dumps, ...
  <NN_run-param2>/
    ...
```

The driver:
1. Computes derived parameters (e.g. shear strain from stress; required forces from stress × area / atoms).
2. Loops over parameter points.
3. For each point: mkdir per-run sub-folder, generate transformed structure, sed-fill (or Python-fill) the input and submit skeletons into the sub-folder, `cd` in, `sbatch`.

**Language choice — to experiment in walk-through.** the user's legacy pattern is bash + awk + sed; Python is a clean alternative for the driver and any parameter math. Constraints:

- LAMMPS input — must be LAMMPS syntax.
- Submit script — must be bash with `#SBATCH`.
- Outer driver — totally free.
- Structure transformation — totally free.

Both bash and Python drivers work with the same `.in.skel` / `.sh.skel` files using bare ALL CAPS placeholders (Python uses `str.replace`, matching sed semantically).

## 8. The cluster bridge

### Mount

Each cluster gets its own mountpoint: `~/cluster-mounts/<cluster>/` corresponds to `/cmmc/ptmp/<user>/` (cmmg case) or the user's equivalent ptmp on other MPCDF clusters. Set up via sshfs by the user.

### Permission model

- **Read** (`ls`, reading logs, status files, anything that just looks) — free, pilot acts without prompting.
- **Write / delete / move / create** on cluster paths — pilot proposes in chat ("I'm going to write `submit.slurm` to `~/cluster-mounts/cmmg/.../<run>/` — OK?"), the user confirms, then pilot executes.
- **Sbatch / job submission** — always strict-A. Pilot drafts the `sbatch` command, the user runs it in his terminal. No exception.

### Survivability

The mount is a *window* on cluster storage, not a duplicate. If cluster TMP gets wiped, the mount disappears with it. Closure-time mile-pebble curation pulls a *compressed copy* to Mac storage (backed up) — this is what makes the project survivable from the laptop alone.

### Files outside the mount

- POTENTIALS (`/cmmc/ptmp/<CLUSTER_USER>/POTENTIALS/`) is inside the mount on cmmg — pilot can verify potential files exist before submit.
- `$HOME` / system modules / system potentials are reference-only — pilot trusts paths in submit scripts; failures fall to layer-2 mechanical fix.

## 9. Workflow: opening a project

1. The user starts a chat in a context that doesn't yet have a project folder.
2. Pilot + the user discuss the science. **No files are created yet.** This is the co-development phase. Pilot is a co-thinker on the question, not a code generator.
3. The user says **"ok, let's start."** This is the explicit transition.
4. Pilot creates `~/Desktop/SIMULATIONS/<sim-project-id>/`, drafts `project.md` with frontmatter (id, name, started date, etc.) and a body capturing the why + current approach. Light vocab fields (material_system, potential, etc.) get filled in from what the discussion already revealed; the rest stay empty for now.
5. Pilot asks any missing high-leverage questions (does this have an admin parent? primary cluster?) and writes the answers in. Deadlines never come up unless the user volunteers.

The *initial* discussion and a *fork* discussion (when the project's question drifts and a new project gets opened) have the same shape — both produce a vocab pass plus a written project.md. There's just one "project-opening" mode.

## 10. Workflow: running a thread

1. The user signals the next thread (e.g. "ok, next let's create the perfect crystal" or pilot proposes from project.md).
2. Pilot creates `<NN_step>/thread.md` with `question:` and `status: active` in frontmatter; opens a brief narrative body.
3. Thread-level files appear: driver script if multi-run, submit + input skeletons, helper scripts as needed.
4. Runs spawn (see §11). thread.md narrative gets updated as work happens.
5. **Closure** triggered when the work is done (success) or the question has a verdict (failure of any kind):
   - Pilot proposes the verdict prose + the mile-pebble (name, type, meaning, paths). The user confirms or corrects.
   - Pilot proposes the mile-pebble curation: which files to compress, where to land on Mac for survivability. The user confirms; the user (or pilot via mount, with OK) executes the tar + cp.
   - Pilot updates thread.md frontmatter: `status: succeeded` (or `failed`/`abandoned`), `mile_pebble: {...}`, `verdict: |...`, `closed:` date.
6. Thread closed. If a downstream thread will consume this mile-pebble, it carries `consumes:` pointing back here.

**For partial-success runs** (sweep failed at high-T): pilot escalates to discussion (layer 3). Routing decided by the user: close thread with partial mile-pebble, fork a new thread to investigate the unexpected physics, or adjust scope and retry. Result transcribed into thread.md.

**For reopening a failed thread later** (if the lesson turns out wrong): the closed thread stays closed; reopening is a *new* thread that explicitly `consumes:` the old closure's verdict as input. Cleaner than status-flipping.

## 11. Workflow: running a run

1. Pilot drafts files (driver if relevant, submit + input scripts, transformed structures) into the Mac-side run dir via Write tool.
2. Pilot proposes writing the same files into the mounted cluster path (`~/cluster-mounts/cmmg/<project>/<thread>/<run>/`); the user confirms; pilot writes.
3. Pilot does layer-1 pre-flight: lint submit script (modules match cluster, walltime sensible vs. calibration, partition correct), lint LAMMPS input (basic syntax, fix ordering, version-matched commands), verify referenced files exist on cluster (including potentials in `/cmmc/ptmp/<CLUSTER_USER>/POTENTIALS`), verify all ALL CAPS placeholders substituted.
4. Pilot proposes the `sbatch` command (with --reservation= only if the user said "urgent"). The user runs it in his terminal.
5. Pilot records `queue_job_id`, `submitted_at` in run.yaml.
6. Pilot polls via mount (or via the user pastes of `squeue` / `sacct`) to track `started_at` and progress.
7. **Completion** — pilot reads `log.lammps`, output files, `sacct` info; fills run.yaml's `walltime_used`, per-simulation `ns_per_day`, `time_per_step_per_atom_per_core`, `status`, `outputs`. Updates `canon/cluster-calibration.yaml` with new actuals.
8. **Curation** — pilot proposes which outputs to keep on Mac (`outputs_kept_on_mac`); the user confirms; pilot writes the tar + cp commands (the user executes, or pilot via mount with OK).
9. If this run produced the thread's mile-pebble, thread closure follows (see §10).

## 12. Iteration model

Three layers:

### Layer 1 — pre-flight (silent, highest-leverage)

Before any copy-paste lands in the user's shell, the pilot lints what it wrote:

- Submit script: walltime sensible (consults calibration), modules match LAMMPS version on this cluster, partition correct, n_cores reasonable.
- Environment: every referenced file exists on cluster (including potentials, which are mount-visible).
- Input structure: masses set for all atom types, box type matches intended deformation, periodicity right.
- LAMMPS input: basic syntax lint, fix command ordering, every command valid for the LAMMPS version in use, all ALL CAPS placeholders substituted.

This catches most submit-time errors before they cost a queue slot.

### Layer 2 — silent iteration (mechanical failures)

When a run fails mechanically (script doesn't parse, missing file, module not loaded, LAMMPS errors at setup):

1. The user pastes the relevant chunk of `log.lammps` back (or pilot reads it via mount).
2. Pilot diagnoses: "this is mechanical — wrong fix ordering at NVE→NVT."
3. Pilot proposes the fix.
4. The user confirms; pilot then deletes the failed run directory (both Mac and cluster, with OK) and resubmits.
5. **No thread closure, no verdict, no run.yaml clutter.** The iteration is invisible after success.

The classification "mechanical vs scientific" is the pilot's proposal, the user's confirmation. Default opener: *"This looks mechanical (script syntax / missing file / module mismatch) — silent fix?"*

### Layer 3 — closure logged (success OR scientific failure)

When a run **succeeds**, OR fails for a *scientific* reason (wrong physics decision, real surprise, "nonsense output", partial failure at a specific parameter value in a sweep), full closure with verdict + mile-pebble. This is the thread-level pattern in §10.

### Heuristic

- *Fails before any physics happens* (start-up error, syntax error, missing file) → almost always layer 2.
- *Fails partway through a run, or at a specific parameter value within a sweep* → almost always layer 3. The cleaner the run reaches before erroring, the more likely it's physics talking.

### Self-improvement

Silent iteration doesn't generate thread closures, but the *pilot* still learns. Repeated mechanical mistakes of the same kind → entries in `canon/learnings.md` ("Tendency: gets `fix npt`/`fix nvt` ordering wrong; sanity-check against current LAMMPS docs before writing"). Over time the pilot gets better at layer 1 because of layer 2 corrections.

## 13. Closure and mile-pebbles

The mile-pebble pointer is the **contract between threads**. A well-formed mile-pebble lets downstream threads find, verify, and consume their input. The structure (§5, thread.md) carries:

- `name` — descriptive filename, no defaults.
- `type` — what kind of artifact (lammps-data-file, dump-frame, csv, plot, scalar-number, table, ...).
- `meaning` — what it IS, scientifically. Prose. This is what makes the artifact reusable (or marks it as not).
- `produced_by_run` — provenance pointer to which run sub-folder generated it.
- `paths.mac` / `paths.cluster:*` — where it lives.
- `backup_status` — pulled-to-mac-compressed / cluster-only / pending.

**One mile-pebble per thread** (can be a list if a thread legitimately produces multiple co-equal artifacts, but the default is one). If a thread's output isn't conceptually a single reusable artifact, the thread granularity was probably wrong.

**Verdicts are prose**, not structured. Failed threads carry verdict only (no mile-pebble). The prose explains what was tried and what was learned; downstream threads that consume the failed verdict use the prose to inform their next attempt.

**Reopen pattern**: closed threads stay closed; reopening = a new thread that explicitly `consumes:` the old closure's verdict as input.

**Bidirectional lineage** for forks: parent has `branched_to: [...]`, child has `parent_thread: ...`.

## 14. Archive prep

Vocabulary alignment is the payoff at archive/publish time. When a project closes and is ready for openbis / Zenodo / a public GitHub repo, a future archive module can synthesize a MatCore-compliant (and EMMO/pyiron-friendly) record from `project.md` + `thread.md` files + `run.yaml` files. The structured fields we've been filling lazily during the project become the export bundle's metadata; the narratives become the documentation.

Key alignments that pay off:

- `simulation_type` decomposed into MatCore's mode × algorithm × ensemble × method.
- `potential` carrying `model-type` + `source.openkim_id` (preferred) + DOI.
- `software.name + software.version` (LAMMPS + module version).
- Multi-stage `computation` (minimize → equilibrate → production) maps to MatCore's repeatable `computation` blocks; this is how our `run.yaml`'s `simulations:` list translates cleanly.
- Analysis-as-continuation of the project maps to MatCore's separate `derived-property` (MatCore-Der) records — analysis threads can each emit one Der record linked to the simulation that generated the raw data.

Archive module is **not v0** — defer until a real legacy project provides the first test case.

## 15. Open items (for walk-through and beyond)

For tomorrow's walk-through:

- Pick the small project (new or legacy).
- Two roles: `[Designer]` (sketching design + critiquing tool's friction) and `[Pilot]` (acting as LLM-LAMMPS for the chosen project). Each response is tagged with exactly one of them — see §17.5 for the capability-vs-tag rule and switching.
- Walk produces concrete content for `canon/style/{lammps,shell,python,ovito}.md` (whichever apply).
- Walk surfaces refinements to this architecture — those go back into ARCHITECTURE.md.
- Experiment with bash/awk/sed vs Python for outer driver scripts; settle on a default by end of week.

Deferred to "later versions":

- **Dashboard surface** — both modes: pure chat queries ("what's open?") + live HTML artifact (refreshable Monday-9am page). Confirmed direction; not v0 work.
- **Archive / openbis module** — wait for a real archive use case.
- **MCP / gradation-B execution** — letting the pilot run sbatch via the user's mac shell. Wait for trust to accumulate over weeks.
- **EMMO IRI verification** — pin at archive time, not now.
- **raven / viper / NHR-Erlangen specific cluster details** — fill in opportunistically when first used.

Open small questions:

- `cluster-calibration.yaml` seed numbers for cmmg × {EAM, MEAM, ACE} × {equilibrium NVT/NPT, minimization} — populate from first real runs.
- Concrete first content for `canon/learnings.md` — most current entries can be seeded from this architecture's hard rules + Anthropic feedback memory; first session of walk-through will produce real additions.

## 16. End-to-end example (folder layout)

A small but realistic sim-project on cmmg, showing the full structure at a moment when 3 threads exist (2 closed, 1 active with both an attempt and runs).

### Mac side

```
~/Desktop/PROJECTS/<GRANT>/<SUBPROJECT>/                              <- admin parent (read-only)
  project.yaml                                                 (email-helper-owned)
  papers/, slides/, ...

~/Desktop/SIMULATIONS/cuAl-disloc/                           <- sim-project (LLM-LAMMPS-owned)
  project.md
  01_create-crystal/                                          <- thread (succeeded)
    thread.md                          status: succeeded
    01_NVT-300K-10ns_equilibrate/      <- run
      input-NVT-300K.lammps
      submit.slurm
      run.yaml
      Cu-fcc-10x10x10-relaxed.data    (mile-pebble, pulled-to-mac-compressed)
      log.lammps                       (small, pulled)
      dump-thermo-every-1ps.dat        (small, pulled)
  02_create-dislocation/                                      <- thread (succeeded)
    thread.md                          status: succeeded
    attempt-1-volterra/                <- failed attempt, lazily nested
      input-volterra.lammps
      submit.slurm
      run.yaml
      log.lammps                       (small, pulled — diagnostic)
    attempt-2-anderson-cottrell/       <- live attempt that worked
      02_anderson-cottrell-insertion/  <- run inside this attempt
        input-anderson-cottrell.lammps
        submit.slurm
        run.yaml
        Cu-edge-dislocation-Anderson-Cottrell.data  (mile-pebble)
        log.lammps
  03_equilibration/                                           <- thread (active)
    thread.md                          status: active
    nvtshear_dislo.py                  (outer driver — Python flavor)
    input-template-NVT.lammps.skel
    submit-template-NVT.slurm.skel
    01_temperature-sweep-NVT-100-500K/ <- run
      T-100K_NVT-10ns/
        input-NVT-T100K.lammps
        submit.slurm
        log.lammps
        Cu-equilibrated-NVT-T100K.data
        dump-thermo-T100K.dat
      T-200K_NVT-10ns/ ...
      T-300K_NVT-10ns/ ...
      run.yaml
```

### Cluster side (via mount; same structure, different paths)

```
~/cluster-mounts/cmmg/cuAl-disloc/                  <- mirrors /cmmc/ptmp/<CLUSTER_USER>/cuAl-disloc/
  01_create-crystal/
    01_NVT-300K-10ns_equilibrate/
      input-NVT-300K.lammps
      submit.slurm
      log.lammps
      Cu-fcc-10x10x10-relaxed.data    (still here too; Mac has compressed copy for survivability)
      dump-positions-every-1ps.lammpstrj   (big; cluster only)
      dump-thermo-every-1ps.dat
  02_create-dislocation/
    attempt-2-anderson-cottrell/
      02_anderson-cottrell-insertion/
        ...
  03_equilibration/
    01_temperature-sweep-NVT-100-500K/
      T-100K_NVT-10ns/
        ...
```

### Global state (Mac)

```
canon/
  preferences.md
  lessons.md
  learnings.md
  vocabulary.yaml
  clusters.yaml
  cluster-calibration.yaml
  style/{lammps,shell,python,ovito}.md
  templates/submit-cmmg.slurm.skel
  tools/{tools-catalog.md,tool-card.skel,<id>.card.yaml}
```

---

## 17. Concurrency model: pilot/designer modes, dashboard, inbox

The user works on multiple projects in parallel. Sessions of LLM-LAMMPS — each
in its own Cowork window — may all see the same `<REPO_ROOT>/`
and the same project archives. Without coordination, two sessions can
race on the framework canon (`canon/`, ARCHITECTURE.md) or
on per-thread files inside one project.

Set 2026-05-31 during Thread 03 of `ni-a0-cij-eam-meam`, after the user
flagged that the prior model implicitly assumed a single serial session.

### 17.1 Three modes

Every session is in one of three modes, declared at startup:

- **pilot** — works on ONE project, possibly one thread of it. Writes
  ONLY to that project's files (Mac archive + cluster mount). Reads
  framework canon (`canon/*`, ARCHITECTURE.md) but does NOT write to
  it. If a pilot session surfaces a new rule
  during its work, it appends a *proposal* to
  `canon/proposals-inbox.md` rather than editing canonical files
  directly.

- **designer** — works on framework canon. No project context.
  Writes to `canon/*` and ARCHITECTURE.md. Reviews and merges
  proposals from the inbox.

- **designer+pilot** (mixed) — concrete project work that ALSO
  produces framework changes (this is what most of the early
  bootstrap sessions of LLM-LAMMPS have looked like). Should become
  the exception once the inbox pattern is established; the steady-
  state alternative is "pilot writes proposals → designer merges
  later."

### 17.2 Invariants

- **At most one session in `designer` or `designer+pilot` mode at any
  one time.** (The "designer lock.") Multiple pilot sessions in
  parallel are fine *iff* their scopes are disjoint.
- **Disjoint pilot scopes**: a pilot owns writes to its project (or
  its thread within a project). Two pilots on the same project +
  same thread is a collision; two pilots on the same project +
  different threads is OK but discouraged (project.md is shared);
  two pilots on different projects is fully fine.
- **Framework canon writes**: only the designer (or designer+pilot)
  session. Pilots are read-only here.
- **Behavioural-rule writes**: durable behavioural rules live in
  `canon/learnings.md` and are written only by the designer; a pilot
  that surfaces one routes it through `canon/proposals-inbox.md`.
  (Retired 2026-07-28: these used to live in a separate host-provided
  "auto-memory" store. See §6.4.)
- **One source of truth, one generated public snapshot (2026-09-25).**
  This repo is private and authoritative. The public repo
  `<GITHUB_USER>/LLM-LAMMPS-framework` is produced from it by
  `canon/templates/export-public.sh` (allowlist + word substitutions +
  the identity lint as a gate; see `canon/templates/public/`). Nobody
  edits the public checkout by hand — the next export overwrites it.
  A designer session that changed framework files runs the export as
  step 7 of its close-out (`canon/session-startup.md`) and hands the
  user the commit/push recipe. What stays private by construction:
  `SESSIONS.md`, the proposals inbox, lessons, learnings, preferences,
  `clusters.yaml`, `environments.md`, the capabilities captures,
  `canon/local/`.

### 17.3 Mode transitions

- **pilot → designer+pilot** (promotion): requires the designer
  lock; check no other designer/designer+pilot session is active in
  the dashboard. If lock free, promote; update SESSIONS.md.
- **designer+pilot → pilot** (demotion): always allowed. Releases
  the designer lock. Useful when the framework work in a mixed
  session is done but pilot work continues (e.g., waiting on cluster
  jobs).
- **designer → closed**, **designer+pilot → closed**, **pilot →
  closed** (wrap-up): standard close. Updates SESSIONS.md from
  `active` to `recently_closed`.

### 17.4 Session-startup ritual

Every session, at startup, performs the ritual codified in
`canon/session-startup.md`:

0. Environment gate (added 2026-07-28): identify the machine from
   `canon/local/.this-machine` (NOT from `hostname` — a Cowork shell runs
   in an isolated VM, not on macOS); verify `canon/local/` exists at all;
   verify the simulation root and cluster mount are actually reachable.
   A missing folder is usually just an unconnected one — ask the user to add
   it; a connected-but-empty mount is EITHER a stale macOS TCC grant (fix:
   re-connect the folder) OR sshfs staleness (fix: remount) — classify by
   whether reads fail with a permission error, and never conclude the data
   is gone. Designer work may proceed without them; pilot work may not.

1. Read `<REPO_ROOT>/SESSIONS.md` (active-sessions dashboard),
   resolved relative to this repo.
1b. Reconcile open loops (added 2026-08-20): if ANY entry — `active` or
   `recently_closed` — has a non-empty `in_flight`, get one `sacct` line
   from the user and reconcile it before asking for scope, then clear the
   reconciled fields. An open loop belongs to the framework, not to a
   project: `in_flight` was a note to a resuming session, and between
   2026-08-04 and 2026-08-20 four projects' handed-over submissions went
   unreconciled for 13–15 days because that session never came — including
   one silent FAILURE nobody saw for a fortnight.
2. Ask the user (via `AskUserQuestion` or chat) the mode and the scope.
3. Cross-check against the dashboard:
   - pilot on a scope already owned → warn and ask whether to take
     over, work on a different thread, or abort.
   - designer/designer+pilot while another holds the lock → warn
     and refuse to proceed until the other closes or demotes.
4. Self-register in SESSIONS.md (auto, no the user confirmation needed).
5. Brief the user on the agreed mode, scope, files this session OWNS,
   and files this session WILL NOT TOUCH.
6. Proceed with normal work.

Mid-session, if the user says "now let's work on X" where X is outside
the current scope, the pilot re-runs steps 3–5 of the ritual.

### 17.5 Role tagging in responses

The user wants a **clean visual separation of the two processes**. The rule:
**capability is a session property; the tag is a per-response identity,
and it is always exactly one hat.**

**Capability vs. tag — the distinction that was missing.** A session may
*register* in SESSIONS.md as `pilot`, `designer`, or `designer+pilot`.
`designer+pilot` means only "this session is *allowed* to do both" (it
holds the designer lock) — it is a capability, not a voice. The bracketed
token `[Designer+Pilot]` is **banned from response tags entirely.** <!-- lint-ok:role-tag -->

**Every response leads with exactly one tag: `**[Pilot]**` OR
`**[Designer]**`** — never both, never blended. This is the user's
at-a-glance check on which voice produced the turn.

**No exceptions.** The tag is required on *every* response — including
one-line confirmations, acknowledgements, clarifying questions, and bare
tool-result relays. There is no response too short to tag. A response
that ships without a tag, or with the banned combined tag, is a process
error; the next response self-corrects and notes the miss.

**The hat follows the work, deterministically:**
- touches project / cluster / science / thread files → `**[Pilot]**`
- touches framework canon / tool cards / ARCHITECTURE →
  `**[Designer]**`

**One response = one hat (hard).** If a single request needs both, do the
dominant role's part, tag it, and state that the other part is queued for
a role switch — do not merge the two into one message. Consecutive
responses each carry their own single tag.

**Switching — two triggers:**
1. *the user-explicit* — "invoke designer", "back to pilot", or a request
   that is plainly the other role's work.
2. *Auto* — the agent notices the next action belongs to the other role
   (e.g. a canon edit) and, **if the session holds that capability**,
   switches.

If the session does NOT hold the designer lock and a designer action is
needed, the agent cannot wear the Designer hat: it either acquires the
lock (announced) or, as a pure pilot, routes the change through
`canon/proposals-inbox.md`.

**Every switch is announced on its own line under the tag — never
silent:**

```
**[Designer]**
↳ switched Pilot→Designer: editing canon (the role-tag rule).
```

Enforcement note: the original failure was *not* a dropped tag — the
canon itself sanctioned `[Designer+Pilot]`, so the agent followed canon <!-- lint-ok:role-tag -->
that disagreed with the user's intent (2026-06-01 Ni-hydride session). The
durable levers are: this section, the copy in `canon/learnings.md`
(read at every session start via the startup ritual), and the
greppable lint `canon/templates/lint-role-tag.sh` that flags any canon
file re-introducing the bracketed combined tag.

### 17.6 Dashboard schema (SESSIONS.md)

Top-level file `<REPO_ROOT>/SESSIONS.md` carries one
entry per active session and a `recently_closed` tail for browsing.
Schema example in `canon/session-startup.md`. Key fields per entry:
`session_id`, `mode`, `scope`, `started`, `last_active`,
`owns_writes_to` (list of dirs/files), `in_flight` (sbatch jobs or
ongoing operations), `notes`.

Self-registration is automatic on session startup; `last_active` is
updated by the session on every major action; the entry moves to
`recently_closed` on wrap-up.

`in_flight` is the one field whose obligation OUTLIVES its entry: an open
loop is not owned by the session that opened it. A session that closes with a
non-empty `in_flight` states that in its `summary:`, and the NEXT session of
any scope reconciles it at startup (§17.4 step 1b). Added 2026-08-20.

### 17.7 Proposal inbox (canon/proposals-inbox.md)

Single append-only markdown file. Pilots append proposals (new
lessons, preference updates, ARCHITECTURE refinements, feedback
memories). Designer reads from the top, merges in batches, edits
prose, drops into the target canonical file, marks the proposal
`status: merged` (or `rejected` with reason). Schema in
`canon/proposals-inbox.md` header.

This eliminates the lesson-numbering race entirely: only the
designer session ever assigns L-numbers.

### 17.8 Per-thread checkpoint instead of global CHECKPOINT.md

The previous CHECKPOINT.md at `<REPO_ROOT>/CHECKPOINT.md`
served as the "read me first when joining cold" entry point. With
parallel sessions, a single global checkpoint becomes a contention
point.

Replacement:
- **`thread.md`** carries the per-thread state (frontmatter, design,
  runs, closure) — it IS the per-thread checkpoint, no separate
  file needed.
- **`project.md`** carries per-project status (open threads,
  closed threads, planned threads).
- **`SESSIONS.md`** carries the cross-project "who's working on
  what right now."

The legacy CHECKPOINT.md is retired (moved to
`.retired-CHECKPOINT.md` with a notice at top pointing readers at
SESSIONS.md + the relevant thread.md). Historical CHECKPOINT.md
content remains accessible.

### 17.9 Practical: the worked example

Set up:
- Session A is `pilot` on `Ni-A0-CIJ-EAM-MEAM / 03_LATTICE-CONSTANT-AT-300K`,
  waiting on cluster jobs.
- The user wants to start a new project. He opens Session B.
- Session B's startup ritual: reads SESSIONS.md, sees Session A is
  `pilot` (no designer lock held). Asks the user mode + scope.
- The user chooses `designer+pilot` for the new project. Lock is free
  → Session B proceeds, registers as `designer+pilot`.
- Session A continues to wait (no conflict; pilot scope is
  disjoint from Session B's project).
- When Session B finishes its framework changes for the new
  project, it demotes to `pilot` (or closes). The designer lock
  is now free again for another framework session if needed.

### 17.10 Open questions still

- **Stale-session GC**: what if a session crashes without removing
  itself from SESSIONS.md? Probably a `last_active` cutoff (e.g.,
  if `last_active` > 24 h ago and no live process, treat as orphan
  and offer to remove). Defer until we see this happen.
- **Race on SESSIONS.md self-register**: if two sessions both
  register at the same millisecond, one's write wins. Mitigation:
  each session reads SESSIONS.md before EVERY major action that
  depends on the designer lock; if its own entry is gone, re-add.

---

*End of architecture v0 draft. Refinements from walk-through merge back in.*
