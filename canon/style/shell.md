# LLM-LAMMPS — Style guide for shell commands

Pilot consults before any shell command Write. Rules here are the
materialization of relevant entries in `../lessons.md` plus standing
conventions.

---

## 1. SSH / SCP / SSHFS — always explicit user (L21)

**Every** ssh, scp, rsync, sshfs command in this project includes the
username explicitly:

```bash
ssh <CLUSTER_USER>@<CLUSTER_HOST> "<remote command>"
scp <CLUSTER_USER>@<CLUSTER_HOST>:<remote path> <local path>
sshfs <CLUSTER_USER>@<CLUSTER_HOST>:/cmmc/ptmp/<CLUSTER_USER> ~/cluster-mounts/cmmg
```

Never the bare-host form (`ssh <CLUSTER_HOST>…`). The user's local SSH config may
resolve it, but every other context (this session, a different agent, a
different machine, a script copy-pasted into a notebook for sharing)
does not have that config. Explicit-user is portable.

For ssh that runs a long-lived command (mount, tunneling), include
`-o ServerAliveInterval=30 -o ServerAliveCountMax=3` to detect dead
connections promptly.

## 2. Compression — zstd default; `-19` for mile-pebble curation (L17)

`zstd` over `gzip` for everything in this project. Faster compress,
smaller ratio, much faster decompress, on the file types we care about
(LAMMPS `.data`, `.dump`, `.log`).

Defaults:

```bash
# In-flight / scratch — fast
zstd <file>             # level 3 default

# Mile-pebble curation (cluster → Mac archival) — max ratio
zstd -19 -c <file> > <file>.zst

# Streaming compress over ssh (for mile-pebble pulls)
ssh <CLUSTER_USER>@<CLUSTER_HOST> "zstd -19 -c <remote-path>" > <local-path>.zst
```

Decompress: `zstd -d <file>.zst` (or `unzstd <file>.zst`).

`.zst` extension always. Do not double-suffix (`.data.zst`, not
`.data.zst.zstd`).

## 3. Bash strictness — every submit script

Every submit script (and any non-trivial standalone shell script in
this project) starts with:

```bash
#!/bin/bash
set -euo pipefail
```

For submit scripts specifically (`learnings.md` Submit-script discipline):

```bash
module purge
module load <lammps/version>
cd "$SLURM_SUBMIT_DIR"

# Existence check for every referenced file
for f in <input.in> <potential files...> <data files...>; do
  [[ -r "$f" ]] || { echo "Missing: $f" >&2; exit 1; }
done

LMP_BIN="${LMP_BIN:-lmp}"

# Notification helper -- pre-flighted like any other input (see 6)
export LMPS_NOTIFY_EMAIL="<NOTIFY_EMAIL>"
NOTIFY_LIB="${LMPS_NOTIFY_LIB:-/cmmc/ptmp/<CLUSTER_USER>/BIN/slurm-notify.sh}"
[[ -r "$NOTIFY_LIB" ]] || { echo "Missing notify helper: $NOTIFY_LIB" >&2; exit 1; }
# shellcheck source=/dev/null
source "$NOTIFY_LIB"
lmps_notify_context PROJECT <project-id>
lmps_notify_context THREAD  <thread-dir>
lmps_notify_arm

srun "$LMP_BIN" -in <input.in> -screen none
```

`--job-name` is descriptive (matches the run-dir slug, no
`job1`/`test`). `--reservation=the user` only when the user says "urgent".

## 4. Rules from lessons.md

- **L11** — `module purge` before any `module load` (deterministic env).
- **L16** — `set -euo pipefail` + file-existence pre-flight in every submit script.
- **L17** — zstd default; `-19` for mile-pebble curation (§2).
- **L21** — always explicit SSH user (§1).

(No remaining placeholder slots — L11 and L16 reconstructed from
transcript on 2026-05-30, see lessons.md numbering notes.)

## 5. Standing conventions (not lessons)

### Path quoting

Quote variables in paths: `cd "$SLURM_SUBMIT_DIR"`, not `cd
$SLURM_SUBMIT_DIR`. Spaces in user-folder paths (e.g.,
`~/Library/Application Support/…`) break unquoted expansion.

### Heredoc for multi-line remote commands

```bash
ssh <CLUSTER_USER>@<CLUSTER_HOST> bash <<'EOF'
  cd /cmmc/ptmp/<CLUSTER_USER>/Ni-A0-CIJ-EAM-MEAM
  ls -la
EOF
```

Single-quoted `'EOF'` prevents local shell from expanding `$variables`
before sending.

### No bare `rm -rf` on cluster paths

Cluster cleanup is a separate, explicit operation. Pilot proposes; the user
runs. Never embedded inside a chained `&&` sequence.

## 6. Job notification e-mail -- Slurm's mail is a backstop, not the message

**Slurm's `--mail-type` mail has a subject line and an EMPTY BODY, and the
subject is boilerplate-first.** What arrives is

```
Slurm Job_id=22730593 Name=NiH-CYC2-RATEB-EAM Ended, Run time 03:41:12, COMPLETED, ExitCode 0
```

so a phone or a narrow mail list shows `Slurm Job_id=2273...` and nothing
else: the job name is off the right edge, the status never appears, and the
submission directory -- the only thing that makes the mail actionable -- is
not in the message at all. Slurm offers no way to add a body. Therefore:

**Every submit script sends its own notification.** Source
`slurm-notify.sh` (canonical copy `canon/templates/slurm-notify.sh`,
deployed per cluster at the `notify.helper` path in `canon/clusters.yaml`)
and call `lmps_notify_arm` after the pre-flight checks, before the `srun`.
It sends STARTED at arm time and exactly one of COMPLETED / FAILED
(with the exit code) / TIMEOUT-OR-CANCELLED (on Slurm's SIGTERM) at the end.

- **Subject**: `[LMPS] <STATUS> <job name> <job id>`. Status is
  front-loaded so it survives truncation at any width; `[LMPS]` is there so
  the mail is filterable.
- **Body**: full job name, **absolute** `SLURM_SUBMIT_DIR` (L-absolute-paths
  applies to mail exactly as it applies to hand-overs), working directory,
  status + exit code, cluster/partition/ranks/node, start + end + wall,
  the stdout and stderr paths, and the last 15 lines of each. Add whatever
  else identifies the run with `lmps_notify_context KEY VALUE` -- at minimum
  PROJECT and THREAD.
- **The helper is pre-flighted, not defaulted away.** A missing helper
  aborts the submit script before the run, in the same existence-check loop
  as the `.in` and the potential. Never `source ... || true`: a
  notification that silently stops arriving is the exact failure class
  (`learnings.md`, "a stale write-listing looks like a successful no-op").
- **Slurm's own mail stays armed as a backstop**, `--mail-type=FAIL,TIME_LIMIT`
  only. BEGIN and END are off -- the helper covers those with a real body.
  FAIL and TIME_LIMIT stay because they are the cases where the helper cannot
  run: node failure, OOM-kill, SIGKILL. A doubled FAIL mail is intended.
- **If no MTA answers on the compute node**, the helper writes the message
  to `NOTIFY-<jobid>.txt` in the submission directory and prints a
  `NOTIFY FALLBACK:` line to stdout. That is a degraded state to fix, not a
  normal one; the per-cluster `notify.mta_on_compute_nodes` field in
  `clusters.yaml` records whether it has been verified. **Verify it once
  per cluster with `canon/templates/slurm-notify.probe.slurm`** -- one
  core-minute, and it is not optional: "the job exited 0" says nothing
  about whether a mail left the node.
- **Probe a mailer BOTH ways -- on PATH and at its absolute path.** On cmmg
  compute nodes (verified 2026-08-26, job 22731708) `command -v sendmail`
  finds nothing while `/usr/sbin/sendmail` is executable. Testing only the
  first silently degrades to `mail` and loses the MIME header; testing only
  the second breaks on a cluster that ships sendmail on PATH. `slurm-notify.sh`
  tests `command -v` first, then `-x /usr/sbin/sendmail`.
- **Slurm's cluster name need not be ours.** The body prints
  `SLURM_CLUSTER_NAME`, which on cmmg is `cmmc`; a mail therefore reads
  `cmmc / s.cmmg`. Expected, not a bug -- but the same class as L42: our
  key for a machine is not the machine's name for itself.
