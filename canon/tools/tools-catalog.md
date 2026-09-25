# LLM-LAMMPS — tools catalog

One-line index of the tool cards in `canon/tools/`. Pinned in session-start
state so the pilot knows what tools exist; the full `<id>.card.yaml` is read
only when a tool is actually about to be used.

See ARCHITECTURE.md §6 "tools registry" for the model: canon holds only
**cards** (plain-file contracts), never tool code. Tool code lives in its
own repo, deployed to `~/bin/` on Mac AND the cluster. Cards describe both
(A) external tools the user already owns and (B) emergent tools promoted from
repeated pilot hand-work (the 3+ rule — see `canon/learnings.md`).

Card template: `canon/tools/tool-card.skel`.

## Conventions

- Card file: `canon/tools/<id>.card.yaml`. Catalog line: `id` — purpose — `run_where` — owner — verified-status.
- `run_where: large-data->cluster` tools (big structures, big trajectories)
  NEVER run on the Mac; the pilot prepares a cluster invocation through the
  §8 bridge (read-free inspect, write-with-OK, strict-A for sbatch).
- Don't guess invocations. A card with `last_verified: pending` is a stub —
  verify against the tool's `--help`/repo before relying on it.

All tools are installed on `$PATH` via `~/bin/` on **both** Mac and cluster,
so `exec.mac` and `exec.cluster` are the same bare invocation.

## entries

| id | purpose | run_where | owner | verified |
|----|---------|-----------|-------|----------|
| lego | crystal structure generator (rotated/cut cells → LAMMPS/IMD) | large-data->cluster | external (github.com/__GH__/LEGO) | 2026-06-01 |
| dcreator | parallel Volterra dislocation inserter (huge cells) | large-data->cluster | external (github.com/__GH__/dcreator) | 2026-04-11 |
| lego-tools | suite: cut/shift/analyze/change-box/pbc-wrap/make-box/nearest-atoms/remove-per-atom | large-data->cluster | external (github.com/__GH__/LEGO-TOOLS) | 2026-04-19 |
| afc | atomic format converter (XYZ ↔ LAMMPS ↔ CEL) | large-data->cluster | external (github.com/__GH__/LEGO-TOOLS) | 2026-04-19 |
| lammps-compile-n-bench | LAMMPS build recipes + portable PACE/ACE benchmark for cmmg/cmti/raven/viper | cluster | external (github.com/__GH__/LAMMPS-compile-n-bench) | 2026-07-28 |
| mu-scan | mu-scan tree loader + per-mu isotherm/verdict summariser (mc/sites + gcmc) | mac | internal (~/DEVEL/MU-SCAN-LOADER) | 2026-08-25 |

Notes:
- `lammps-compile-n-bench` is a **reference card**, not an invocable CLI: it
  documents how LAMMPS is built per machine and what throughput is measured.
  Read it before proposing a new build, a module stack, or any cross-machine
  performance claim. It is the source of truth behind the raven/viper/cmmg
  entries in `canon/clusters.yaml`.
- `lego-tools` is one card covering the eight `lego-*` binaries (shared
  atomio I/O lib); `afc` ships in the same repo but gets its own card
  (distinct purpose). See each `<id>.card.yaml` for the full contract.
- `run_where: large-data->cluster` is the default routing; light inspection
  calls (`lego-analyze`, a small `afc` convert) are fine on the Mac — see
  the per-card gotchas.
