---
name: llm-lammps
description: Entry point for atomistic simulation work driven through the LLM-LAMMPS framework (LAMMPS on HPC clusters). Use whenever the user mentions simulations, LAMMPS, a simulation project or thread, runs, sbatch/Slurm jobs, a cluster (cmmg, raven, viper, cmti), potentials (EAM, MEAM, GRACE, ML potentials), relaxations, minimizations, MD equilibration, dislocations, grain boundaries, lattice constants, elastic constants, dumps or trajectories, OVITO analysis, "which simulation projects are open", "start a new simulation project", "close a thread", or "mirror the results to the Mac". Also use for changes to the framework itself (canon, ARCHITECTURE, lessons, tool cards).
---

# LLM-LAMMPS — framework entry point

This skill does **not** contain the framework. It routes you into it and
guards the few rules that must hold before anything else happens. The
framework is a set of plain files in the LLM-LAMMPS repo; **canon is the
ground truth, this file is only the doorbell.**

## 1. Locate the repo

Look for a folder containing `ARCHITECTURE.md` **and** `canon/session-startup.md`
— `LLM-LAMMPS` under the user's `DEVEL/` tree (renamed from
`LLM-LAMMPS-public` on 2026-09-25; the GitHub repo is `<GITHUB_USER>/LLM-LAMMPS`,
private). Check the connected folders first. Modules / Python / venvs per
cluster: `canon/environments.md`.

If you cannot find it, **stop and ask** where it is. Do not reconstruct
the framework from this file, and do not browse the `DEVEL/` tree to guess
at simulation state — `DEVEL/` holds framework code and tooling, not the
simulations.

## 2. Run the startup ritual

Read `<REPO_ROOT>/canon/session-startup.md` and follow it verbatim,
starting at **step 0** (environment gate). It is the authority; if it
disagrees with anything below, it wins. In outline:

0. **Environment gate.** Identify the machine from `canon/local/local.yaml`.
   Verify `canon/local/` exists (fresh clones have placeholders only).
   Verify the simulation root and cluster mount are reachable — a session
   that cannot see them (typically a cloud sandbox, which cannot add
   folders mid-session) may do designer work but **must not** do pilot work.
1. Read `<REPO_ROOT>/SESSIONS.md` — who owns what, who holds the designer lock.
2. Ask the user: **which simulation folder** (always ask, never assume),
   the **mode** (`pilot` / `designer` / `designer+pilot`), and the **scope**.
3. Cross-check for scope collisions and the designer lock.
4. Self-register in `SESSIONS.md` (do not ask permission for this).
5. Brief the user: session id, scope, what this session owns and will not touch.
6. Proceed — one role tag per response.

Then read `canon/learnings.md`, `canon/preferences.md` and `canon/lessons.md`
before doing project work, and the relevant `canon/style/*.md` before
writing any LAMMPS input or shell script.

## 3. The five hard rules (non-negotiable)

Repeated here because a session that skips them does damage before it
ever reads canon. Full text in `ARCHITECTURE.md` §2.

1. **The LLM owns the write channel.** The user never types into project
   files. He speaks; you transcribe into `project.md` / `thread.md`.
2. **Descriptive file names always.** No `dump.out`, no `run1/`,
   no `restart.data`. You pick the name; he should not have to ask.
3. **Cluster access is gated.** You never reach HPC directly or around his
   auth. `sbatch` is *always* strict-A: you draft the command, **he runs it
   in his own shell**. Cluster file *reads* via the mount are free; writes
   are proposed and confirmed first.
4. **Brainstorm mode is the default for new design questions.** Co-develop
   the science first. Do not open with options-dumps and question batteries,
   and do not push for scoping until he signals "ok, let's start."
5. **Plain files only.** Markdown, YAML, JSON, parquet. No databases.
   Ephemeral surfaces — the task list, chat scratch — are **not storage**:
   any lesson or decision worth keeping lands in its plain file the moment
   it surfaces.

## 4. Three rules that have cost real jobs

- **Probe before production.** Every new or edited LAMMPS input gets a
  short probe `sbatch` first. Verify clean exit, the "ALL PHASES COMPLETE"
  marker, and all `Performance:` lines — *then* propose production. The
  probe is also the walltime-calibration source (scale `--time` from its
  measured timesteps/sec).
- **Never run LAMMPS or any MPI code on a login node**, and never install
  into cluster `$HOME` (tight quota — venvs, pip/conda caches, TF and
  `nvidia-cu12` wheels, model caches and build trees all belong under
  scratch). Login nodes are for building, downloading and submitting.
- **Every submit script sends its own notification mail.** Slurm's
  `--mail-type` mail is subject-only with an empty body and the job name
  truncated off the right edge — it is a BACKSTOP (`FAIL,TIME_LIMIT` only),
  not the message. Source the deployed `slurm-notify.sh` (per-cluster path in
  `canon/clusters.yaml` → `notify.helper`) and call `lmps_notify_arm` after
  the pre-flight checks, before the `srun`; pre-flight the helper like any
  other input and never `source ... || true`. Full rule and skeleton:
  `canon/style/shell.md` 6. On a cluster with no `notify:` block yet, deploy
  the helper and verify it once with `canon/templates/slurm-notify.probe.slurm`
  before relying on it.

## 5. Role tag

Tag every response with exactly one hat: `**[Pilot]**` (project, cluster,
science, thread files) or `**[Designer]**` (canon, tool cards,
ARCHITECTURE). The combined form is banned as a response tag. Announce
every switch on its own line. See `ARCHITECTURE.md` §17.5.

## 6. Surfacing a new rule

As a pilot, do **not** edit canon. Append a proposal to
`canon/proposals-inbox.md`; a designer session merges it. Fix the class,
not the instance.
