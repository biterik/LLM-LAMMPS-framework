#!/bin/bash
# preflight-local.sh -- EXECUTE a SLURM submit script and the LAMMPS inputs it drives locally, before any cluster probe.
#
# The cluster tree is mirrored under a local sandbox root: every absolute cluster path (CLUSTER_ROOT/...) in the copied
# inputs and scripts is rewritten to SANDBOX/..., srun/sbatch/module/scontrol are stubbed, the SLURM_* variables are set,
# and the script runs under `bash -x` with the real LAMMPS (`lmp` on PATH; the pip wheel of the same LAMMPS version as the
# cluster module is enough). What this catches: every execution-order error in the inputs (reset_timestep with a
# time-dependent fix, f_ID after unfix, compute not current, ...), every path/cd/pipefail error in the script, missing
# files, wrong placeholder substitution. What it cannot catch: cluster-only physics (ML-PACE if the local build lacks it ->
# --substitute-pace runs the same logic with the EAM block), performance, MPI decomposition (`processors` lines are
# commented out for the local run), the mail transport.
#
# usage: preflight-local.sh --script SUBMIT.slurm --cluster-dir /abs/cluster/path/of/the/thread \
#            [--cluster-root /cmmc/ptmp/USER] [--sandbox DIR] [--standin REL/PATH=LOCALFILE ...] \
#            [--substitute-pace EAMBLOCKFILE] [--timeout SECONDS] [--omp N] [--array-task I]
#   --script       the submit script (any location; its directory is taken as the thread's local source directory)
#   --cluster-dir  where that thread lives on the cluster (what the script's own paths assume)
#   --standin      provide a file the script expects at CLUSTER_ROOT/REL/PATH (e.g. a relaxed cell) from a local file
#   --substitute-pace FILE  replace `pair_style pace` + its pair_coeff line by the two lines in FILE (local build has no ML-PACE)
# exit 0 = script finished with exit 0 AND its DONE marker is in the output; the report names what was found.
# Author: <AUTHOR> (created with LLM-LAMMPS), 2026-10-12.
set -uo pipefail
SCRIPT=""; CDIR=""; CROOT="${PREFLIGHT_CLUSTER_ROOT:-/cmmc/ptmp/${USER:-unknown}}"; SANDBOX="${PREFLIGHT_SANDBOX:-$HOME/preflight-sandbox}"; TMO=1800; OMP=1; ATASK=""; PACEFILE=""
STANDINS=()
while [[ $# -gt 0 ]]; do case "$1" in
  --script) SCRIPT="$2"; shift 2;; --cluster-dir) CDIR="$2"; shift 2;; --cluster-root) CROOT="$2"; shift 2;;
  --sandbox) SANDBOX="$2"; shift 2;; --standin) STANDINS+=("$2"); shift 2;; --substitute-pace) PACEFILE="$2"; shift 2;;
  --timeout) TMO="$2"; shift 2;; --omp) OMP="$2"; shift 2;; --array-task) ATASK="$2"; shift 2;;
  *) echo "unknown argument $1" >&2; exit 2;; esac; done
[[ -r "$SCRIPT" && -n "$CDIR" ]] || { echo "usage: --script SUBMIT.slurm --cluster-dir /abs/cluster/thread/dir" >&2; exit 2; }
command -v lmp >/dev/null || { echo "no lmp on PATH (pip install lammps)" >&2; exit 2; }
SRC="$(cd "$(dirname "$SCRIPT")" && pwd)"; SNAME="$(basename "$SCRIPT")"
[[ "$CDIR" == "$CROOT"/* ]] || { echo "--cluster-dir must start with --cluster-root ($CROOT)" >&2; exit 2; }
LDIR="$SANDBOX${CDIR#$CROOT}"
mkdir -p "$LDIR" "$SANDBOX/_stubs" "$SANDBOX/BIN"
# 1. copy the thread's small files (inputs, scripts, tools, manifests); large data via --standin
( cd "$SRC" && find . -maxdepth 3 -type f \( -name '*.in' -o -name '*.slurm' -o -name '*.py' -o -name '*.sh' -o -name '*.txt' -o -name '*.dat' -o -name '*.tmpl' -o -name '*.part' -o -name '*.yaml' \) -size -2M -print0 | tar --null -cf - -T - ) | tar -xf - -C "$LDIR"
for s in "${STANDINS[@]}"; do rel="${s%%=*}"; loc="${s#*=}"; mkdir -p "$(dirname "$SANDBOX/$rel")"; cp -f "$loc" "$SANDBOX/$rel"; done
# 2. rewrite cluster paths -> sandbox; neutralise `processors`; optional pace substitution
find "$LDIR" -maxdepth 2 -type f \( -name '*.in' -o -name '*.slurm' -o -name '*.py' -o -name '*.sh' \) -exec sed -i "s|$CROOT|$SANDBOX|g" {} +
find "$LDIR" -maxdepth 2 -type f -name '*.in' -exec sed -i 's/^processors /#processors (commented by preflight-local) /' {} +
if [[ -n "$PACEFILE" ]]; then
  for f in $(grep -l '^pair_style *pace' "$LDIR"/*.in 2>/dev/null); do
    python3 - "$f" "$PACEFILE" <<'PY'
import sys,re
f,p=sys.argv[1],sys.argv[2]; L=open(f).read().split('\n'); B=[l for l in open(p).read().split('\n') if l.strip()]
out=[]; i=0
while i<len(L):
    if re.match(r'^pair_style\s+pace',L[i]):
        out.append('# preflight-local: pair_style pace substituted by '+p); out+=B; i+=1
        while i<len(L) and not re.match(r'^pair_coeff',L[i]): out.append(L[i]); i+=1
        i+=1; continue
    out.append(L[i]); i+=1
open(f,'w').write('\n'.join(out))
PY
  done
fi
# 3. stubs
cat > "$SANDBOX/_stubs/srun" <<STUB
#!/bin/bash
# preflight stub: run the command here, LAMMPS single process (+OpenMP threads if requested)
args=("\$@"); while [[ "\${args[0]:-}" == -* ]]; do if [[ "\${args[0]}" == "-n" || "\${args[0]}" == "-N" ]]; then args=("\${args[@]:2}"); else args=("\${args[@]:1}"); fi; done
if [[ "\$(basename "\${args[0]}")" == lmp* && $OMP -gt 1 ]]; then exec "\${args[@]}" -sf omp -pk omp $OMP; fi
exec "\${args[@]}"
STUB
printf '#!/bin/bash\necho "preflight stub: module $*" >&2\n' > "$SANDBOX/_stubs/module"
printf '#!/bin/bash\necho "Submitted batch job 999999 (preflight stub: $*)"\n' > "$SANDBOX/_stubs/sbatch"
printf '#!/bin/bash\n# preflight stub: job ends in 10 min\necho "JobId=1 JobName=preflight EndTime=$(date -d "+10 minutes" +%%Y-%%m-%%dT%%H:%%M:%%S) TimeLimit=00:10:00"\n' > "$SANDBOX/_stubs/scontrol"
printf '#!/bin/bash\necho "preflight stub: $0 $*"\n' > "$SANDBOX/_stubs/squeue"; cp "$SANDBOX/_stubs/squeue" "$SANDBOX/_stubs/sacct"
chmod +x "$SANDBOX/_stubs/"*
[[ -r "$SANDBOX/BIN/slurm-notify.sh" ]] || { echo "NOTE: no $SANDBOX/BIN/slurm-notify.sh -- copy canon/templates/slurm-notify.sh there (the script pre-flights it)"; }
# 4. SLURM environment from the #SBATCH header
jn=$(grep -m1 -oE '^#SBATCH +--job-name=\S+' "$SRC/$SNAME" | sed 's/.*=//'); nt=$(grep -m1 -oE '^#SBATCH +--ntasks=[0-9]+' "$SRC/$SNAME" | sed 's/.*=//')
arr=$(grep -m1 -oE '^#SBATCH +--array=\S+' "$SRC/$SNAME" | sed 's/.*=//')
export PATH="$SANDBOX/_stubs:$PATH" SLURM_SUBMIT_DIR="$LDIR" SLURM_JOB_NAME="${jn:-preflight}" SLURM_JOB_ID=1 SLURM_NTASKS="${nt:-1}" SLURMD_NODENAME=preflight-local SLURM_JOB_NODELIST=preflight-local SLURM_NNODES=1
export LMPS_NOTIFY_LIB="$SANDBOX/BIN/slurm-notify.sh" OMP_NUM_THREADS="$OMP"
if [[ -n "$arr" ]]; then lo="${arr%%-*}"; hi="${arr#*-}"; hi="${hi%%%*}"; export SLURM_ARRAY_TASK_ID="${ATASK:-$lo}" SLURM_ARRAY_TASK_MIN="$lo" SLURM_ARRAY_TASK_MAX="$hi" SLURM_ARRAY_JOB_ID=1; fi
# 5. run
LOG="$LDIR/preflight-local_${SNAME%.slurm}.log"
echo "=== preflight-local: $SNAME  (sandbox $LDIR, omp $OMP, timeout ${TMO}s, array task ${SLURM_ARRAY_TASK_ID:-n/a}) ==="
( cd "$LDIR" && timeout "$TMO" bash -x "./$SNAME" ) >"$LOG" 2>&1; rc=$?
echo "script exit code: $rc   (124 = timeout)"
echo "DONE markers in output: $(grep -cE '(PROBE|JOB) DONE' "$LOG")   LAMMPS errors: $(grep -c '^ERROR' "$LOG" "$LDIR"/*/*.log "$LDIR"/*.log 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
grep -hE '^ERROR|Last command|Missing|No such file|command not found|failed|ended without|exit code [1-9]' "$LOG" "$LDIR"/*/*.log 2>/dev/null | grep -v '^+ ' | sort -u | head -20
leftover=$(grep -l "$CROOT" "$LDIR"/*.in "$LDIR"/*.slurm 2>/dev/null | head -3); [[ -z "$leftover" ]] || echo "WARNING: cluster root still present in: $leftover"
echo "full log: $LOG"
[[ $rc -eq 0 ]] && grep -qE '(PROBE|JOB) DONE' "$LOG"
