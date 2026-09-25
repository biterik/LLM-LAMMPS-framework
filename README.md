# LLM-LAMMPS — framework

A plain-file, LLM-agnostic framework for running atomistic simulation projects
(LAMMPS on HPC clusters) **end-to-end through an LLM assistant** — input decks,
analysis, and the *documentation and reasoning* alongside them — while keeping a
human firmly in the loop for anything that touches a cluster.

> **Status: research preview / work in progress.** This is an evolving design,
> not a finished tool. The canon and architecture docs are the real artifact;
> expect them to change.

> **This repository is a generated, framework-only snapshot.** It is exported
> from the author's private working repository (which additionally holds the
> live session dashboard, the framework-change inbox, project-specific lessons,
> personal preferences and real cluster definitions). Everything here is
> placeholder-only: no real usernames, hosts or paths, and the person running
> the framework is referred to as "the user". Issues and pull requests are
> welcome and will be folded back into the source; direct edits to this repo
> are overwritten on the next export.

## What it is

The framework is a set of **plain text/markdown/YAML files** that an LLM reads at
the start of a session and treats as ground truth. There is deliberately no
bespoke software layer: project state lives in files the LLM re-reads, so the
system stays inspectable, version-controllable, and portable across LLM
providers.

Core ideas:

- **Identity rides on a canonical `id`, not folder paths.** Workstation and
  cluster paths are *observations* of one project; folders may diverge, the
  `id` is the anchor. Rename/move within tracked roots is self-healing.
- **The workstation is the safe record.** Cluster scratch is fragile and
  unbacked; the workstation is backed up. Expensive-to-regenerate artifacts are
  pulled (compressed) to the backed-up side on closure, so a project is
  *survivable from the workstation alone*.
- **Propose → human runs, for the cluster.** The LLM never reaches HPC directly
  or around the user's auth. It drafts commands; the user executes them in their
  own SSH session. Probe before any production submission.
- **Concurrency model.** Sessions self-register in a `SESSIONS.md` dashboard
  and take a `pilot` (move a project forward) and/or `designer` (change the
  framework itself) role, with a single designer write-lock.
- **Tools as cards, not code.** Canon holds only *tool cards* (mechanical
  contracts); tool implementations live in their own repos and binaries.

## Repository layout

```
ARCHITECTURE.md          The framework spec (start here). §17 = concurrency model.
brainstorm-notes.md      Design rationale and the "why" behind the decisions.
canon/                   The runtime substrate the LLM reads as ground truth:
  clusters.example.yaml    A fictional cluster definition — copy to clusters.yaml and adapt.
  session-startup.md       The startup ritual each session runs.
  examples-catalog.md      How worked examples are catalogued.
  style/                   LAMMPS-input and shell style guides.
  templates/               Lint scripts, skeletons, Slurm notify helper, curated-mirror script.
  tools/                   Tool catalog + tool cards (lego, lego-tools, dcreator, afc, …).
  local.example/           Template for the gitignored identity overlay.
skills/llm-lammps/       Packaged entry point so the ritual self-triggers.
examples/                Illustrative material.
```

Files the framework *expects* but this snapshot does not ship (they are yours
to create; the ritual tells you when one is missing):

| File | Role |
|---|---|
| `canon/clusters.yaml` | your clusters — start from `canon/clusters.example.yaml` |
| `canon/local/` | your real identity overlay — start from `canon/local.example/` |
| `SESSIONS.md` | the live session dashboard — created by the first session |
| `canon/proposals-inbox.md`, `canon/lessons.md`, `canon/learnings.md`, `canon/preferences.md` | grow with use; the ritual creates them empty |

## Setup

### 1. Install the skill

The framework only works if a session actually *engages* it. `skills/llm-lammps/SKILL.md`
is the trigger: it fires on "simulations", "LAMMPS", "runs", a project or thread,
a cluster name, a potential, an `sbatch` — and routes the session into
`canon/session-startup.md`.

**Claude Cowork (desktop app).** Either zip the skill folder's contents so that
`SKILL.md` sits at the root of the archive, name it `llm-lammps.skill` and send
it into a conversation to save it to your account (it then triggers in every
session), or simply connect this repo as a folder in the session (the skill is
picked up while the folder is connected).

**Other LLM hosts.** The skill file is plain markdown with YAML frontmatter.
Paste its body into whatever the host calls a system/project instruction. Nothing
in the framework depends on the skill mechanism — it is a doorbell, not a
dependency.

### 2. Describe your cluster(s)

```
cp <REPO_ROOT>/canon/clusters.example.yaml <REPO_ROOT>/canon/clusters.yaml
$EDITOR <REPO_ROOT>/canon/clusters.yaml
```

Keep it placeholder-only (`<CLUSTER_USER>`, `<CLUSTER_HOST>`, …). The real
values go into the overlay in the next step.

### 3. Create your local identity overlay

Real cluster usernames, hostnames, notification addresses and home paths appear
in the framework only as placeholders:

| Placeholder | Meaning |
|---|---|
| `<CLUSTER_USER>` | Your username on the HPC cluster |
| `<CLUSTER_HOST>` | The cluster login host (e.g. `login.mycluster.edu`) |
| `<NOTIFY_EMAIL>` | Address for Slurm job mail (`--mail-user`) |
| `<MAC_USER>` | Local workstation username, where it appears in example paths |
| `<GITHUB_USER>` | Your GitHub handle, where sibling tool repos are cited |
| `<DEVEL_ROOT>` | Your dev tree (where the tool repos live) |
| `<REPO_ROOT>` | The root of *this* repo, resolved from wherever it is checked out |
| `<AUTHOR>` | Your name, in the author line of generated scripts |

The real values go in `canon/local/`, which is gitignored:

```
cp -R <REPO_ROOT>/canon/local.example <REPO_ROOT>/canon/local
$EDITOR <REPO_ROOT>/canon/local/local.yaml            # machine map + local roots
$EDITOR <REPO_ROOT>/canon/local/clusters.local.yaml   # ssh user/host/scratch, notify email
```

The startup ritual checks for it at step 0 and refuses cluster work without it.
Keeping the overlay in step across several workstations (private git repo, or
cloud-drive + symlink) is described in `canon/local.example/README.md`.

### 4. Guard the scrub boundary

```
python3 <REPO_ROOT>/canon/templates/lint-no-identity.py
```

Fails if any *tracked* file contains a value from `canon/local/`, or matches a
generic identity pattern (email, `/Users/<name>`, `ssh user@host`, a real
scratch path). Run it before every push; wire it as a `pre-push` hook if you
want it enforced.

## Running a session

The framework needs to see three trees: this repo, the simulation folder, and
the cluster mount. In Claude Cowork, connect all three with **"Add folder"**.
Mount the cluster over sshfs *before* connecting it, or the folder connects but
reads as empty. Step 0 of the startup ritual verifies all three and says what is
missing rather than improvising a substitute.

The reference configuration was developed on Slurm clusters at a German
academic computing centre; the example cluster file reflects that shape.

## License

MIT — see [LICENSE](LICENSE).
