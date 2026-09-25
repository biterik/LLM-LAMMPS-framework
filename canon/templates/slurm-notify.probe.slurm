#!/bin/bash
# ---------------------------------------------------------------
# slurm-notify.probe.slurm — one-off verification of slurm-notify.sh
# on a NEW CLUSTER (or after a cluster rebuild). Costs ~1 core-minute.
#
# It answers the one question the helper cannot answer from the Mac:
# does a compute node on this cluster have a working MTA? If it does,
# two mails arrive with bodies; if it does not, the run dir holds a
# NOTIFY-<jobid>.txt and the .out carries NOTIFY FALLBACK lines.
#
# Array task 0 exits 0  -> expect [LMPS] STARTED + [LMPS] COMPLETED
# Array task 1 exits 1  -> expect [LMPS] STARTED + [LMPS] FAILED (exit 1)
#                          AND Slurm's own subject-only FAIL backstop.
#
# Render <NOTIFY_EMAIL> and <CLUSTER_USER> before submitting, run it
# from a scratch directory, then record the verdict in
# canon/clusters.yaml -> clusters.<name>.notify.mta_on_compute_nodes.
#
# Author: <AUTHOR>  (created with LLM-LAMMPS)   Date: 2026-08-26
# ---------------------------------------------------------------
#SBATCH -J LMPS-notify-probe
#SBATCH --partition=s.cmmg
#SBATCH --ntasks=1
#SBATCH --hint=nomultithread
#SBATCH -t 00:05:00
#SBATCH --array=0-1
#SBATCH -o slurm-%x_%A_%a.out
#SBATCH -e slurm-%x_%A_%a.err
#SBATCH --mail-type=FAIL,TIME_LIMIT
#SBATCH --mail-user=<NOTIFY_EMAIL>

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:?}"

export LMPS_NOTIFY_EMAIL="<NOTIFY_EMAIL>"
NOTIFY_LIB="${LMPS_NOTIFY_LIB:-/cmmc/ptmp/<CLUSTER_USER>/BIN/slurm-notify.sh}"
[[ -r "$NOTIFY_LIB" ]] || { echo "Missing notify helper: $NOTIFY_LIB" >&2; exit 1; }

echo "=== MTA INVENTORY on ${SLURMD_NODENAME:-?} ==="
for m in sendmail mail mailx; do
  printf '%-10s: %s\n' "$m" "$(command -v "$m" 2>/dev/null || echo 'not found')"
done
printf '%-10s: %s\n' "/usr/sbin/sendmail" \
  "$([[ -x /usr/sbin/sendmail ]] && echo executable || echo 'not executable')"

# shellcheck source=/dev/null
source "$NOTIFY_LIB"
lmps_notify_context PROBE   "notification transport check"
lmps_notify_context NODE    "${SLURMD_NODENAME:-?}"
lmps_notify_arm

echo "task ${SLURM_ARRAY_TASK_ID}: pretending to be a LAMMPS run"
sleep 5

if [[ "${SLURM_ARRAY_TASK_ID:-0}" -eq 1 ]]; then
  echo "task 1: exiting non-zero ON PURPOSE to exercise the FAILED path"
  exit 1
fi

echo "PROBE DONE"
