# LLM-LAMMPS — Brainstorm Notes

Started: 2026-05-27. Mode: open exploration, no convergence yet.

Companion project: **Email + Todo Helper** (`~/Codes/AI-Assistant-for-general-projects/`).
Loosely coupled via a shared canonical project `id`.

---

## The reframe (the user, 2026-05-27)

The RELATED_CONTEXT.md framing as "LLM-assisted RDM" is **wrong-shaped**.
The user's actual vision, in his words:

- **NOT** an RDM project. **NOT** a workflow project. Explicitly **not**
  AiiDA, **not** pyiron, **not** the "rigid, self-important" workflow-engine
  family. Bets that LLMs will outpace ontology adoption as the organizing
  layer of research work.
- Workflow tools are the wrong abstraction because they presume a known
  DAG. Real science — *"finding shit out"* — is non-DAG: false starts,
  branches, "wait let me try X instead", reformulating the question.
- The tool's job: **be a co-thinker that compresses the distance from
  idea to result**. Given a problem or scientific question, develop
  strategies with the user (which may fail — that's the point), write the
  LAMMPS input scripts, the run scripts (with loops), the analysis
  scripts, the aggregation, the visualization (OVITO), the figures.
  Knowing the *why* is essential — both to drive the LLM and to remind
  the user later.
- The user does the **least amount of typing and syntactic mediation** in
  LAMMPS / Python / bash / awk / OVITO / Jupyter possible. Fast loop:
  idea → running job → analysed data → figure.

## The structural tension

Speed-of-thought iteration generates chaos. So:

- After a week, the user can't remember where things were, what was tried,
  what's unfinished. → tool needs **continuity scaffolding** for
  re-entry.
- The user should be able to **hand a project to a PhD student** to take
  over from where he left off.
- A **dashboard** shows: active / on hold / dropped / needs attention,
  across projects.

## On FAIR / ontologies / openbis

- Endgoal is **scientific insight**, not FAIR compliance.
- BUT — finished work does get archived/published, and that should be
  *painless*, not a separate publication phase.
- The user's mental model (2026-05-27): *"structured research data is a
  natural byproduct of a LLM-first approach that is generated on the
  fly without me ever having to worry about it or metadata schema,
  ontologies, vocabularies etc."* — structure emerges, it isn't
  declared.
- Existing vocabularies / schemas / ontologies used **from the
  beginning where it makes sense** — not exhaustively, not as an
  upfront tax.

## Downstream-workflow compatibility (the user, 2026-05-27)

Important refinement of the anti-workflow stance:

- Once a successful solution emerges, it should be **relatively easy
  to lift into a (pyiron-)workflow** *on the workflow side*.
- **LLM-LAMMPS never produces workflows itself.** The heavy lifting of
  translating-to-workflow lives in the workflow tool, not in this one.
- LLM-LAMMPS's only obligation is to **use the same words/concepts**
  where possible, so a downstream translator (human or LLM) doesn't
  have to bridge vocabulary drift.

**Principle: shared vocabulary, asymmetric responsibility.**
Vocabulary is free; framework machinery is expensive.

Two layers where vocab alignment likely pays off:
- **Operational/engineering (pyiron-aligned):** job, calculator-style
  engine wrapper, parametric study, restart, generic output container,
  resource spec. Pays back at the moment of lifting to workflow.
- **Scientific/domain (EMMO / NFDI-MatWerk-aligned):** material
  system, interatomic potential, lattice constant, primary observable.
  Pays back at search across past work and at archive time.

### Retroactive metadata + legacy ingestion (the user, 2026-05-27)

**Legacy ingestion is a first-class capability**, confirmed by the user
as "a big thing". The tool earns trust by being able to walk into a
real, messy, pre-existing LAMMPS project folder and tell back
something true about what's there — *before* it ever asks the user to do
anything its way.

The LLM doesn't only *emit* metadata going forward — it can also
**reconstruct** it from the project's artifacts and history: LAMMPS
input/log/dump files, scratch markdown, directory layout, file naming
patterns, git history if present.

Consequences:
- "Light upfront" is reinforced: catch-up is always available, so
  declaring schemas first is even less necessary.
- **Adopting existing projects** is a viable mode, not a special
  case. Likely *the* trust-establishing use case.
- The identity layer (canonical `id`, marker file) has to handle
  "this folder existed before the tool did" gracefully — no demand
  that the user rename anything or restructure.
- At archive / publish / openbis-push time, the LLM does a
  structured pass to fill gaps before the data leaves.
- Useful mid-project too: "I've been at this for three weeks, my
  notes are a mess — clean up and tell me what I've actually done."
- Possible v0 entry point: a "show me what you see" command run
  against an existing folder.

## How to evaluate any feature idea

A feature for this tool earns its keep if it does at least one of:

1. Reduces time from idea → plot.
2. Lets the user re-enter a project fast after a gap.
3. Lets a PhD student take over a project the user leaves.
4. Makes the eventual archive/publish step nearly free.
5. Captures the *why* in a form both the user and the LLM can use later.

Features that only serve archiving and don't touch (1)–(3) are
*v-much-later*.

## Open threads to explore

### The interaction shape
- What does the moment-to-moment experience look like? Conversational
  in Cowork? CLI? A blend? An always-open project pane that knows
  what's running?
- The autonomy spectrum: when does the LLM ask first vs. just do?
  the user's phrasing — *"writes with me (or alone if clear enough)"* —
  implies a spectrum, not a switch.

### The continuity layer — converging on a model (2026-05-27)

**The user's historical practice (the data we're designing from):**
One `howto-<topic>.txt` per project. Pasted `pwd`, `date`, the shell
commands as executed. Notes on what was edited ("changed Temperature
in script"). Sometimes pasted results, sometimes just commands. Queue
job IDs. Runtime logs (used to size core/time allocation). Inline
reactions ("shit, didn't relax", "shit, forgot to set the variable
correctly… doing again…"). The big win: copy-paste the chain back
into the shell to replay.

**Where it broke:** when a chain turned out wrong, the *logical* move
was to go up in the file, mark the prior step wrong, and start a new
chain from there. But that destroyed monotonic timestamps and the
linear narrative. Compounded → unreadable. Compounded → `OLD/OLD2/
WRONG/` folders because dead data couldn't be thrown away (might
still be useful, might even be right later).

**The structural diagnosis:** a flat file is linear-in-time;
exploratory work is linear-in-logic. They coincide only until
something forks. After enough forks, the howto.txt and the actual
reasoning diverge.

### Proposed model: thread + mile-pebble (the user's term)

A **thread** is the basic unit. Linear-in-time within itself. Starts
with a question/hypothesis, ends with a **verdict**: either a
mile-pebble (a checked output the next thread can consume) or a
"didn't work, because…" closure.

- Forking happens by **closing the current thread and opening a new
  one with a parent pointer** to the branching moment. No upward
  editing. No lost monotonicity.
- Old/wrong data is no longer orphaned: it lives in *threads with a
  closure*. Re-openable if a closed thread turns out to have been
  right after all. → `OLD/OLD2/WRONG/` directories become
  unnecessary.
- A thread file is plain markdown — light frontmatter (status,
  question, parent, mile-pebble produced) + free-form body in the user's
  existing howto.txt voice (pasted commands, timestamps, inline
  reactions).
- **Runnability is preserved**: the thread file remains
  copy-pasteable into the shell. With LLM in the loop, "rerun
  thread-007 with cutoff = 10 instead of 8" is plausibly one
  sentence, not copy-paste at all.

### Organising threads so chaos doesn't reassert itself

- **Status as primary axis.** {active, blocked, paused, succeeded,
  failed, abandoned}. Dashboard groups by status.
- **Parent/child + mile-pebble dependencies → a forest per project.**
  The forest IS the project's logical structure.
- **A "rough sketch" file at project root**, LLM-maintained — the
  page the user reads first when re-entering after a week: what we're
  trying to learn, best current understanding, open threads, last
  mile-pebble reached.
- **LLM as orchestrator.** Queries against the thread graph: "what's
  open?", "what's queued?", "what did we decide about X last week?".
  Active nudges: "this thread's been quiet — pause or abandon?".

### Three reframes from the user's howto.txt experience

1. **Time is the wrong primary axis. The question is.**
   howto.txt mixed them; threads separate them.
2. **OLD/OLD2/WRONG folders are just unverdicted threads.**
   The fix is closure lines, not folder hygiene.
3. **The runnable-script-of-record property is preserved, not
   abandoned.** LLM-augmented, copy-paste itself becomes optional.

### Thread granularity — converged (2026-05-27)

**Rule of thumb:** a thread earns its own existence if its mile-pebble
would plausibly be reused, referenced, or branched from. Otherwise
it's just steps inside another thread. The user confirmed this on the
dislocation example (perfect crystal is reusable for many defect
types → its own thread; build-and-insert as a single step is not).

Concrete examples:
- Build 10×10×10 Cu fcc block → one thread.
- Build Cu fcc block + Volterra screw dislocation → two threads
  (perfect block is a reusable mile-pebble).
- Cutoff sweep 6/7/8 → one thread (single question).
- "Equilibration won't stabilise" debugging → one thread, with forked
  sub-threads for different timestep/thermostat/box attempts.

Within a thread, false starts and "shit, forgot to set the variable"
stay **inline** in the howto.txt voice. Forks happen only when the
work goes genuinely sideways (different geometry, different
question).

### Folder layout — convention (2026-05-27)

**Flat, numbered, one folder per thread.** Matches the user's existing
practice; the "phase grouping" (create-sample) is conceptual and
doesn't need to be physical.

```
01_create-crystal/
  in.create_crystal, crystal.data, log.lammps, ...
  thread.md   (status: succeeded, mile-pebble: crystal.data)
02_create-dislocation/
  in.insert_dislocation, dislocation.data, ...
  thread.md   (status: succeeded, mile-pebble: dislocation.data)
03_relaxation/
  ...
```

**Each folder gets a `thread.md`** carrying status, question/
hypothesis, verdict, mile-pebble pointer, parent thread (if forked).

### Handling failed attempts — lazy nesting

A failed attempt does **not** become `02_create-dislocation_OLD/` or
get a parallel-numbered sibling like `02b_`. The folder stays put;
the failed attempt nests inside as a *labelled* subfolder. The
nesting is **lazy** — it only appears once a retry happens.

```
02_create-dislocation/
  attempt-1-volterra/
    in.insert_dislocation, ...
    thread.md   (status: failed, verdict: "atoms overlapped,
                 Volterra parameter too aggressive")
  attempt-2-anderson-cottrell/        ← live
    in.insert_dislocation, dislocation.data, ...
    thread.md   (status: succeeded, mile-pebble: dislocation.data)
```

Properties:
- **Pipeline order preserved.** No `02b_`, `02_v2_`, `02_REDO_`
  accumulating. Step 02 is always step 02.
- **Failed work is named for what was tried** (`attempt-1-volterra/`)
  — informative, not sediment. Decision history is legible by
  reading the folder.
- **Downstream paths are stable.** Step 03 consumes "the mile-pebble
  of step 02"; the thread graph resolves that to the live attempt's
  artifact. No symlinks needed; thread layer handles "which attempt
  is current".
- **Simple projects never see this nesting.** If every step works
  first try, the layout is identical to the user's flat existing one.

### The invariant: folders are storage, thread.md is the truth

Whether the project is flat-flat or has nested `attempt-*/`
subfolders, the verdict, mile-pebble, parent thread, and status all
live in `thread.md`. Folders are arranged for human scan-ability;
the LLM and dashboard trust the thread files. This is also why
legacy ingestion works — the LLM walks existing folders, drops in
reconstructed `thread.md` files, and the structure is the same
regardless of whether the layout came from this tool or from the user's
habits five years ago.

### Per-job sub-folders (the user, 2026-05-27)

**The user's rule:** every LAMMPS job writes in its own directory,
which also contains the input script and the starting structure
that fed it. Reason: avoid filename collisions from default-named
outputs; keep each job self-contained for diffing and re-running.

This pushes a level **below** the thread folder:

```
03_equilibration/
  thread.md
  01_NVT-300K-10ns/
    in.equilibrate-NVT-300K.lammps
    starting.data
    final-equilibrated-Cu-300K.data
    log.lammps                          (LAMMPS forces; OK, folder is descriptive)
    dump-positions-every-1ps.lammpstrj
    dump-thermo-every-1ps.dat
  02_NVT-300K-10ns_smaller-timestep/    (sibling run, comparison)
    ...
```

`NN_<descriptive>/` for run folders — chronological prefix +
what-the-run-is suffix. `ls` of a thread folder tells you at a
glance what each run was for.

### Hard rule: NO default file names

The user hates `dump.out`-style defaults. Every file the LLM
generates gets a descriptive name. **Captured as a persistent
feedback memory** (`feedback_descriptive_file_names.md`) so it
applies in every future session, not just this one.

### Hierarchy summary

- `<project>/`
- `<project>/<NN>_<step>/` ← thread folder (one thread per step
  for the simple case)
- `<project>/<NN>_<step>/attempt-<N>-<descriptive>/` ← appears
  lazily, only when retries
- `<project>/<NN>_<step>/<NN>_<run-name>/` ← per-LAMMPS-job
  directory (or under `attempt-*/` when both apply)
- `thread.md` at the *live* level (step level when no attempts;
  attempt level when there are attempts).

### Forks: different question vs. different attempt

- **Different attempts at the same question** → nest as
  `attempt-*/` subfolders inside the step folder.
- **Genuinely different question that branched off** → a new thread
  at sibling level, parented to the original. E.g. mid-way through
  `02_create-dislocation/` realising "I want a *pair*" →
  `02_create-dislocation/` (original, closed) and
  `02-pair_create-dislocation-pair/` (new branch, parented).

Same data structure (thread.md with parent pointer); different
*placement* reflects "this is a different physics question" vs.
"this is another shot at the same one."

### Vocabulary / ontology — "where it makes sense"
Two interpretations of the user's caveat:
- **Annotate later**: do the science free-form, then at archive time
  the LLM helps map local terms to EMMO/NFDI-MatWerk. No upfront cost.
- **Constrain lightly upfront**: agreed terms for a few high-value
  fields (material system, potential, simulation type, primary
  observable) so cross-project search/aggregation works for the user
  himself.
- Likely the second is closer in spirit — confirm.

### Laptop ↔ HPC structure — converging (2026-05-27)

**Reality check (the user, 2026-05-27):** existing folders are NOT in
the structured form we just designed. Folders are pretty disordered.
Names diverge across `PROJECTS/` (high-level, DFG / presentations),
`SIMULATIONS/` (compute), and HPCs. Disorder is the *day-one input*,
not an edge case. → tool must be biased toward "works on existing
chaos" over "best when started fresh".

**Locations map (extends email-helper concept):** identity rides on
canonical `id`, paths are observations. One project carries a list
of `{machine, role, path}`:

```
mac:projects     = ~/Desktop/PROJECTS/<GRANT>/<SUBPROJECT>/        (parent context)
mac:simulations  = ~/Desktop/SIMULATIONS/cuAl-disloc/     (compute work)
cluster:JUWELS:project  = /p/project/.../erik/cuAl_disloc/
cluster:JUWELS:scratch  = /p/scratch/.../erik/cuAl_disloc/
cluster:LUMI:project    = ...
```

Handles three realities at once: different names across machines,
multiple clusters as first-class, multiple paths per machine
(scratch vs. project, production vs. exploratory) with explicit roles.

**Parent relationship handles abstraction levels.**
`mac:projects = .../<GRANT>/<SUBPROJECT>/` is the parent project's location
(DFG admin, slides, presentations). The simulation project nests
under it via `parent: sfb1394-a02`. LLM pulls the *why* from parent
when asked. Email-helper already understands `parent` — contract
holds.

### Data placement tiers (MD-shaped)

- **Definition tier** — input scripts, analysis scripts, thread
  files, notes, plots. Small, version-able, lives on Mac, mirrored
  to cluster on submit. Git's domain, LLM's domain.
- **Heavy result tier** — trajectories, large dumps, restart files.
  Stays on cluster, pulled selectively. LLM mediates: "show me the
  dump from the last NVT run" → one sentence; LLM does the fetch.
- **Derived result tier** — analysis outputs, aggregated CSVs, plot
  data. Small enough for Mac; produced on cluster, pulled post-
  analysis.

The tool needs to know which tier each file lives in, to know
what's authoritative where.

### Survivability tier — backup asymmetry (the user, 2026-05-27)

Critical constraint: The user works on **non-backed-up HPC TMP**
directories. His Mac has 2 independent backups. → Laptop must
function as the **safe record of the project**, even though
heavy compute lives on fragile cluster storage.

Implication: each mile-pebble has implicit **backup-worthiness**
derivable from compute cost. Expensive-to-regenerate artifacts
(24h relaxation, 12h thermalization, equilibrated state) get
pulled (gzipped) to laptop on thread closure. Huge trajectories
(1 µs production) stay on cluster — but derived analyses and
*selected restart frames* are small and pullable. LLM can strip
dump fields not needed for restart (positions + velocities + box)
to compress further.

**Closure ritual for a thread:** declare verdict, name mile-pebble,
and (if expensive to regenerate) pull compressed copy to Mac. LLM
proposes; the user confirms.

**The property this gives:** the project is **survivable from the
laptop alone**. Cluster TMP wipe → lose ability to cheaply restart
from intermediate states, but threads, mile-pebbles (compressed),
decisions, scripts, plots, lessons learned all survive. Cluster
becomes a *compute layer the project temporarily uses*, not the
project's home. First-class design constraint.

### LLM ↔ HPC access policy (the user flagged, 2026-05-27)

**Constraint:** LLM should not directly access HPC. Concerns:
(a) admin policy unclear, (b) the user prefers rsync/scp over sshmount.
sshmount = last resort only.

**Structural answer:** LLM never goes around the user's auth; cluster
never sees an LLM doing weird things. From admin perspective every
action is indistinguishable from the user typing in his own SSH
session. No daemon on cluster, no API integration, no separate
LLM credentials.

**Gradation of LLM ↔ HPC interaction:**

- **A — Fully manual.** LLM writes commands; the user copy-pastes into
  his terminal; pastes output back. Maximally safe. Slow.
- **B — LLM runs commands via the user's Mac shell**, using the user's
  existing SSH config + keys (scp, rsync, ssh-and-run). Cluster
  sees the user's normal SSH session. This is what every CLI tool
  already does — LLM is just another agent in the user's shell. No
  separate creds.
- **C — sshmount / SSHFS.** Last resort.
- **D — Daemon or API on cluster.** Don't.

**Recommended default:** B for data movement, A for anything that
submits or modifies cluster state.

- *Fetch job log, check queue, rsync result, pull compressed
  mile-pebble on closure* → B (LLM runs via Mac shell).
- *Submit a job, delete cluster files, anything irreversible* →
  A (LLM prepares submit script + command; the user runs the single
  `sbatch` line; job id flows back to thread.md).

**Submission flow sketch:**
1. The user describes the run.
2. LLM writes `in.production`, `submit.slurm` to project folder.
3. LLM scp's them to cluster (B).
4. LLM shows: `ssh juwels && cd ... && sbatch submit.slurm`.
5. The user runs that one line.
6. Job id captured into thread.md.

Authority for submission stays with the user. Bookkeeping with LLM.
Cluster sees only the user's SSH session.

**Important subtlety:** LLM running shell commands locally (Cowork's
shell tool) is *not* the same as LLM having cluster credentials.
B is the first, never the second. LLM uses the user's `~/.ssh/config`
and ssh-agent like any other process the user starts. Admin-invisible.

### Decisions (2026-05-27)

- **v0 default: strict-A** for everything. LLM prepares commands;
  the user runs them. Relax to B later as trust accumulates over the
  first weeks of use.

### Cluster realities (the user, 2026-05-27)

Five clusters:
- **cmmg** (= cmti, same platform/IP — model as one entry with two
  aliases). Currently the main one. Super stable, downtime ~every
  4 months.
- **raven** (MPCDF, CPU + GPU). Wants to use. Announced downtimes
  ~every 2 weeks.
- **viper** (MPCDF, GPU). Wants to use. Announced downtimes
  ~every 2 weeks.
- **NHR Erlangen**. Wants to use. Stability TBD.

Implications:
- `clusters.yaml` must support aliasing (cmmg ↔ cmti).
- "Job stuck?" diagnostic should know about scheduled downtimes —
  fortnightly MPCDF maintenance windows for raven/viper are
  known-quantity; an idle job during one isn't stuck.
- GPU/CPU distinction is first-class (viper is GPU-only).
- Cluster knowledge accumulates over time per his
  *lessons-learned* principle.

### Legacy ingest pattern

LLM walks candidate Mac folders and candidate cluster folders,
infers correspondences by content sniff (input files, potential
names, paper refs, dates), proposes a draft locations map, the user
confirms/corrects, tool stamps marker file + tentative
`thread.md` skeleton. **Nothing moves. Nothing gets renamed.**
Folders stay as-is — they're just *known* now.

### Open questions (asked of the user 2026-05-27, awaiting answer)

- How many clusters currently? How stable are paths on each — do
  admins move things, or do paths persist for years? Determines
  how aggressively the tool needs to re-verify locations.

### LAMMPS-specific vs. engine-agnostic
- Name suggests LAMMPS-first. Is the design LAMMPS-shaped (e.g. knows
  about `in.*` files, dumps, restart files) or just LAMMPS-as-first-
  target?
- OVITO is in the stack — also Python/Jupyter for analysis. The LLM
  needs to fluently move between LAMMPS input syntax, post-processing
  Python, OVITO Python scripting, plotting.

### LLM-agnostic — operationally
- What does it mean? Files on disk readable by any LLM? A
  model-switching abstraction? "Don't use vendor-proprietary
  features"?
- Implication for prompts/state: project state lives in plain files
  the LLM rereads, not in an opaque LLM-side memory.

### Handoff to a PhD student
- This is a really useful design lens. If the test is *"can someone
  who has never seen this project sit down and continue it tomorrow"*,
  what would the project folder need to contain? That set of artifacts
  is probably very close to what *the user-in-a-week* needs too.

## Themes the design will eventually need to address

- **Identity** — canonical `id`, parent slug, marker file, rename-safe
  (contract with email helper).
- **The journal** — threads + mile-pebbles (see continuity section).
- **The cluster bridge** — Mac ↔ cluster paths, submission, state.
- **The LLM contract** — what state lives where, how the LLM is fed,
  how outputs are checked.
- **Vocabulary** — minimal upfront set + later-mapping layer.
- **The dashboard** — surface for status across projects.
- **The archive path** — painless on-ramp from "this is done" to
  "this is published / on openbis / on Zenodo / wherever."

## Information the tool needs — straw-man categories (2026-05-27)

Sketched for the user to extend / correct / kill / reshape. Not fixed.

1. **Project-level metadata** — id, name, parent, scientific
   question (the *why*), status, light vocab (material system,
   potential, simulation engine, primary observable), locations
   map, collaborators, last activity, links to companion assets
   (papers, slides, openbis entries, email-helper id).
2. **Thread-level metadata** — thread id, project id, question,
   status, parent thread, mile-pebble produced (name + location),
   folder path, timeline, verdict.
3. **Run-level metadata** — per simulation run: queue job id,
   cluster, partition, submitted/started/finished, input file ref,
   output location, status, requested vs. actual resources, notes.
4. **Cluster knowledge** — per HPC: hostname / ssh config,
   filesystem layout ($HOME/$WORK/$SCRATCH), queueing system +
   submission templates, module environment (LAMMPS / OVITO /
   Python), username, allocation ids, quirks.
   *cluster-lammps-info.txt is probably mostly this for one
   cluster — fold in at this layer.*
5. **The user preferences + lessons learned** — *global*, not
   per-project. Default unit styles, go-to potentials per material,
   canonical recipes, "never do X", Python style, plot defaults.
   **The category that must amass over time** — LLM proposes
   additions ("you always use unit style 'metal' here — add to
   preferences?"); the user confirms.
6. **Vocabulary mappings** — local ↔ pyiron ↔ EMMO/NFDI-MatWerk.
   Lazy. Only fields where alignment pays back.
7. **Cross-project graph** — which projects feed which papers,
   which potential calibrations are reused, the dashboard view.
   *Derived*, not stored — computed from walking project.yaml
   files.

### Meta-principle: the information store is *living*

Plain YAML / markdown. Additive — new fields don't break old
projects (they just don't have the field). LLM proposes updates
as it observes patterns; the user confirms. Lessons learned are
first-class. No migration needed when the worldview grows.

### Physical placement straw-man

- Project metadata → `<project-root>/project.yaml`
- Thread metadata → `<project>/<step>/thread.md` (frontmatter + body)
- Run metadata → inside `thread.md` or sibling `runs/` (TBD)
- Cluster knowledge → global `canon/clusters.yaml`
- The user preferences/lessons → global `canon/preferences.md` (grows)
- Vocabulary mappings → global `canon/vocabulary.yaml`
- Cross-project graph → derived, not stored

Plain files. Inspectable. Git-able. LLM-readable AND writable.
No database (yet).

## Decisions captured so far

### 2026-06-01 — Tool integration design (designer session 1557)

Discussion: how to handle/include tools in LLM-LAMMPS. Two tool types the user
named: (A) external tools he already owns, in `~/bin/`, own GitHub repos,
still being developed — e.g. LEGO (github.com/__GH__/LEGO), LEGO-TOOLS
(github.com/__GH__/LEGO-TOOLS), dcreator (github.com/__GH__/dcreator);
(B) emergent tools — operations the pilot hand-rolls repeatedly that
should be promoted to real, tested, documented tools once used 3+ times.
Tools must run on both Mac and cluster; large-data tools (dcreator, lego)
run on the cluster.

DECISIONS (firm):
- **Tool card abstraction.** Both tool types are described to the pilot
  by one plain-file contract — a *tool card* (parallels `style/` and
  `examples-catalog.md`). Fields: id, purpose, upstream repo, per-platform
  invocation (exec.mac / exec.cluster), `run_where` (mac | cluster |
  large-data→cluster), I/O contract, version + `last_verified` stamp,
  gotchas. Pilot reads the card, not the source.
- **Canon holds only cards — never tool code.** Promoted-internal tools
  graduate into their own small repo(s) deployed to `~/bin/` on Mac AND
  cluster, same as the external tools. The framework canon never contains
  a build/test/deploy story; preserves hard rule 5 (plain-file,
  LLM-agnostic substrate).
- **Routing rides §8 cluster bridge.** `large-data→cluster` cards mean the
  pilot prepares a cluster invocation; read-free inspect, write-with-OK,
  strict-A for sbatch. No new permission machinery.
- **Promotion trigger uses existing governance.** learnings.md rule: if
  the pilot hand-rolls the same op 3+ times, it files a proposals-inbox
  entry to promote it; designer session creates the card (+ for internal
  tools, the repo/tests). Same pilot→inbox→designer flow as lessons/style.
- **Drop the hidden `.lmps/` + `~/.lmps/` home-promotion.** The canon is
  currently hidden in `DEVEL/LLM-LAMMPS/.lmps/` while meta-docs sit visible
  at top level — inverted (the most-read-at-runtime material is hidden,
  fighting "the user reads files anytime"). Move canon to a VISIBLE folder in
  `DEVEL/LLM-LAMMPS` (working name `canon/`); demote the `~/.lmps/` home
  move to "maybe later, only if multi-machine becomes real." Keep the
  design-vs-canon boundary as a visible sub-folder split, not hidden-vs-
  visible. Tools cards land at `canon/tools/` + `canon/tools/tools-catalog.md`.

IMPLEMENTED 2026-06-01 (same session):
- Folder name DECIDED: `canon/`. Move done (`.lmps/` -> `canon/`, visible).
- Class-wide path sweep done; ARCHITECTURE.md §3/§6/§16 + §6 "tools
  registry" subsection written; canon/learnings.md "## Tools" added;
  canon/tools/ scaffolded (catalog + tool-card.skel + 3 stub entries);
  lint canon/templates/lint-canon-paths.sh added (clean).

STILL OPEN:
- Fill the 3 external tool cards (lego, lego-tools, dcreator) — needs
  invocation + I/O verification against each repo and `--help` on Mac
  AND cluster. Currently stubs.
- Re-probe ritual detail for version-drift on external tools
  (`tool --version` / `--help` refreshes the card stamp) — captured as a
  learnings.md rule; refine if it proves too loose.
- MCP-wrapping of tools: deferred (against the lazy ethos; CLIs via the
  §8 bridge are enough for now).

## Parking lot

- `cluster-lammps-info.txt` in this folder — to be folded in once
  scope is clearer.
- Prior art surveying — explicitly **deprioritised** by the user for
  AiiDA-class tools. Could still be worth a quick look at lightweight
  things (e.g. `mdsea`, `pymatgen` workflows, ad-hoc Jupyter setups in
  other groups) — but only if the user wants it.
- Possible LLM-side architectural choices: chat-driven (Cowork) vs.
  command-driven (a `lmps` CLI) vs. both with shared state.
