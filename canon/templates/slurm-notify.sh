# LLM-LAMMPS -- Slurm job notification helper (sourced, not executed).
#
# WHY THIS EXISTS
# ---------------
# Slurm's own `--mail-type` mail has a SUBJECT ONLY and an EMPTY BODY.
# The subject is a fixed boilerplate string:
#
#   Slurm Job_id=22730593 Name=NiH-CYC2-RATEB-EAM Ended, Run time 03:41:12, COMPLETED, ExitCode 0
#
# so by the time a mail client has shown "Slurm Job_id=..." the job name is
# already off the right edge, the status never arrives, and the submission
# directory -- the one thing needed to act on the mail -- is nowhere in the
# message at all. Slurm has no option to add a body; the only way to get one
# is to send the mail ourselves from inside the job.
#
# WHAT IT DOES
# ------------
# Sends our own mail at job start and at job end, with
#   subject:  [LMPS] <STATUS> <job name> <job id>      (status front-loaded)
#   body:     full job name, ABSOLUTE submission directory, working
#             directory, status + exit code, cluster/partition/ranks,
#             start/end/wall, stdout+stderr paths, and the tail of each.
# Slurm's own mail stays armed as a BACKSTOP for the cases where this
# helper cannot run at all (node failure, OOM-kill, scancel): see the
# --mail-type rule in canon/style/shell.md 6.
#
# DEPLOYMENT
# ----------
# One copy per cluster, on the cluster, at
#   /cmmc/ptmp/<CLUSTER_USER>/BIN/slurm-notify.sh
# (path recorded per cluster as `notify.helper` in canon/clusters.yaml).
# Submit scripts SOURCE it and pre-flight it like any other input file --
# a missing helper aborts the submit script before the run, it never
# degrades to a silent no-op.
#
# USAGE IN A SUBMIT SCRIPT
# ------------------------
#   export LMPS_NOTIFY_EMAIL="<NOTIFY_EMAIL>"     # same address as --mail-user
#   NOTIFY_LIB="${LMPS_NOTIFY_LIB:-/cmmc/ptmp/<CLUSTER_USER>/BIN/slurm-notify.sh}"
#   [[ -r "$NOTIFY_LIB" ]] || { echo "Missing notify helper: $NOTIFY_LIB" >&2; exit 1; }
#   # shellcheck source=/dev/null
#   source "$NOTIFY_LIB"
#   lmps_notify_context PROJECT ni-h-hydride-cycle-eam
#   lmps_notify_context THREAD  03_CHARGE-DISCHARGE-RATEB-CORRECTED-300K
#   lmps_notify_arm                       # sends STARTED, installs the traps
#
# Everything after `lmps_notify_arm` is covered: a clean exit sends
# COMPLETED, any non-zero exit sends FAILED with the exit code, and the
# SIGTERM Slurm sends at the walltime cap sends TIMEOUT.
#
# Author: <AUTHOR> (created with LLM-LAMMPS)   Date: 2026-08-26
# ---------------------------------------------------------------------

# --- internal state ---------------------------------------------------
_LMPS_N_START_EPOCH=""
_LMPS_N_CONTEXT=""
_LMPS_N_SENT_FINAL=0
_LMPS_N_OUT_OVERRIDE=""
_LMPS_N_ERR_OVERRIDE=""

# lmps_notify_context KEY VALUE
#   Adds one "KEY : VALUE" line to the body of every subsequent mail.
#   Use for project, thread, run tag, mu, temperature -- whatever makes
#   the mail self-explanatory without opening the run directory.
lmps_notify_context() {
    _LMPS_N_CONTEXT="${_LMPS_N_CONTEXT}$(printf '%-12s: %s' "$1" "${2:-}")
"
}

# lmps_notify_files STDOUT_PATH [STDERR_PATH]
#   Optional. Declare the job's stdout/stderr explicitly. Without it the
#   helper asks `scontrol show job` for StdOut/StdErr, which is right in
#   almost every case; use this when the run redirects elsewhere, or on a
#   cluster where scontrol is not reachable from the compute node.
lmps_notify_files() {
    _LMPS_N_OUT_OVERRIDE="${1:-}"
    _LMPS_N_ERR_OVERRIDE="${2:-}"
}

# --- mail transport ---------------------------------------------------
# Tries sendmail, then mail, then mailx. If none delivers, writes the
# message to the submission directory and prints a LOUD line to stdout --
# never silently drops a notification, never fails the job.
_lmps_n_deliver() {
    local subject="$1" body="$2" to="${LMPS_NOTIFY_EMAIL:-}" sm=""
    # Save and restore the caller's errexit: a notification must never be
    # able to kill the job, and must never silently change shell state.
    local _e=0; case "$-" in *e*) _e=1;; esac
    set +e
    if [[ -z "$to" ]]; then
        echo "NOTIFY ERROR: LMPS_NOTIFY_EMAIL is unset; no mail sent." >&2
        [[ $_e -eq 1 ]] && set -e; return 1
    fi

    sm="$(command -v sendmail 2>/dev/null)"
    [[ -z "$sm" && -x /usr/sbin/sendmail ]] && sm=/usr/sbin/sendmail
    if [[ -n "$sm" ]]; then
        printf 'To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' \
            "$to" "$subject" "$body" | "$sm" -t 2>/dev/null
        if [[ $? -eq 0 ]]; then [[ $_e -eq 1 ]] && set -e; return 0; fi
    fi

    if command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$body" | mail -s "$subject" "$to" 2>/dev/null
        if [[ $? -eq 0 ]]; then [[ $_e -eq 1 ]] && set -e; return 0; fi
    fi

    if command -v mailx >/dev/null 2>&1; then
        printf '%s\n' "$body" | mailx -s "$subject" "$to" 2>/dev/null
        if [[ $? -eq 0 ]]; then [[ $_e -eq 1 ]] && set -e; return 0; fi
    fi

    # No MTA reachable from this compute node -- leave the message on disk.
    local dir="${SLURM_SUBMIT_DIR:-$PWD}"
    local f="${dir}/NOTIFY-${_LMPS_N_JOBID:-nojobid}.txt"
    { echo "Subject: $subject"; echo; echo "$body"; } >> "$f" 2>/dev/null
    echo "NOTIFY FALLBACK: no working mailer on ${SLURMD_NODENAME:-this node};"
    echo "NOTIFY FALLBACK: message appended to ${f}"
    [[ $_e -eq 1 ]] && set -e
    return 1
}

# --- identity ---------------------------------------------------------
_lmps_n_identity() {
    _LMPS_N_JOBNAME="${SLURM_JOB_NAME:-<no SLURM_JOB_NAME>}"
    if [[ -n "${SLURM_ARRAY_JOB_ID:-}" ]]; then
        _LMPS_N_JOBID="${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID:-?}"
    else
        _LMPS_N_JOBID="${SLURM_JOB_ID:-<no SLURM_JOB_ID>}"
    fi
    # StdOut/StdErr paths carry %x/%A/%a already expanded -- ask Slurm
    # rather than reconstructing them from the sbatch directives.
    _LMPS_N_OUT=""; _LMPS_N_ERR=""
    if command -v scontrol >/dev/null 2>&1 && [[ -n "${SLURM_JOB_ID:-}" ]]; then
        local sc; sc="$(scontrol show job "$SLURM_JOB_ID" 2>/dev/null || true)"
        _LMPS_N_OUT="$(printf '%s\n' "$sc" | sed -n 's/^ *StdOut=//p' | head -1)"
        _LMPS_N_ERR="$(printf '%s\n' "$sc" | sed -n 's/^ *StdErr=//p' | head -1)"
    fi
    [[ -n "$_LMPS_N_OUT_OVERRIDE" ]] && _LMPS_N_OUT="$_LMPS_N_OUT_OVERRIDE"
    [[ -n "$_LMPS_N_ERR_OVERRIDE" ]] && _LMPS_N_ERR="$_LMPS_N_ERR_OVERRIDE"
    return 0
}

_lmps_n_tail() {   # _lmps_n_tail <label> <path> <nlines>
    local label="$1" path="$2" n="${3:-15}"
    [[ -n "$path" && -r "$path" ]] || return 0
    if [[ -s "$path" ]]; then
        printf -- '--- last %s lines of %s (%s) ---\n%s\n' \
            "$n" "$label" "$path" "$(tail -n "$n" "$path" 2>/dev/null)"
    else
        printf -- '--- %s (%s) is EMPTY ---\n' "$label" "$path"
    fi
}

_lmps_n_body() {   # _lmps_n_body <STATUS> <detail>
    local status="$1" detail="${2:-}" now wall=""
    now="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    if [[ -n "$_LMPS_N_START_EPOCH" ]]; then
        local s=$(( $(date +%s) - _LMPS_N_START_EPOCH ))
        wall="$(printf '%02d:%02d:%02d' $((s/3600)) $((s%3600/60)) $((s%60)))"
    fi
    cat <<EOF
$(printf '%-12s: %s' STATUS   "${status}${detail:+ (${detail})}")
$(printf '%-12s: %s' JOB      "$_LMPS_N_JOBNAME")
$(printf '%-12s: %s' JOBID    "$_LMPS_N_JOBID")
$(printf '%-12s: %s' SUBMITDIR "${SLURM_SUBMIT_DIR:-<unset>}")
$(printf '%-12s: %s' WORKDIR  "$PWD")
$(printf '%-12s: %s' CLUSTER  "${SLURM_CLUSTER_NAME:-?} / ${SLURM_JOB_PARTITION:-?}")
$(printf '%-12s: %s' RESOURCES "${SLURM_NTASKS:-?} tasks on ${SLURM_JOB_NUM_NODES:-?} node(s), first ${SLURMD_NODENAME:-?}")
$(printf '%-12s: %s' TIME     "started ${_LMPS_N_START_HUMAN:-?}   now ${now}${wall:+   wall ${wall}}")
${_LMPS_N_CONTEXT}$(printf '%-12s: %s' STDOUT "${_LMPS_N_OUT:-<unknown>}")
$(printf '%-12s: %s' STDERR   "${_LMPS_N_ERR:-<unknown>}")

$(_lmps_n_tail stdout "$_LMPS_N_OUT" 15)
$(_lmps_n_tail stderr "$_LMPS_N_ERR" 15)
EOF
}

_lmps_n_send() {   # _lmps_n_send <STATUS> <detail>
    local status="$1" detail="${2:-}"
    _lmps_n_deliver "[LMPS] ${status} ${_LMPS_N_JOBNAME} ${_LMPS_N_JOBID}" \
                    "$(_lmps_n_body "$status" "$detail")" || true
}

# --- traps ------------------------------------------------------------
_lmps_n_on_exit() {
    local rc="${1:-0}"
    [[ $_LMPS_N_SENT_FINAL -eq 1 ]] && return 0
    _LMPS_N_SENT_FINAL=1
    if [[ "$rc" -eq 0 ]]; then
        _lmps_n_send COMPLETED "exit 0"
    else
        _lmps_n_send FAILED "exit ${rc}"
    fi
}

_lmps_n_on_term() {
    [[ $_LMPS_N_SENT_FINAL -eq 1 ]] && return 0
    _LMPS_N_SENT_FINAL=1
    # Slurm sends SIGTERM at the walltime cap (and on scancel) before the
    # KillWait grace period expires; this is the only chance to report it.
    _lmps_n_send TIMEOUT-OR-CANCELLED "SIGTERM from Slurm"
}

# lmps_notify_arm
#   Sends the STARTED mail and installs the EXIT + TERM traps. Call it
#   AFTER the pre-flight existence checks and BEFORE the srun.
lmps_notify_arm() {
    _LMPS_N_START_EPOCH="$(date +%s)"
    _LMPS_N_START_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    _lmps_n_identity
    trap '_lmps_n_on_exit $?' EXIT
    trap '_lmps_n_on_term' TERM
    _lmps_n_send STARTED ""
}
