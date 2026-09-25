# canon/local/ — the identity overlay (never committed)

Everything in this repo is **scrubbed**: cluster usernames, hostnames,
notification addresses and local absolute paths appear only as
placeholders (`<CLUSTER_USER>`, `<CLUSTER_HOST>`, `<NOTIFY_EMAIL>`,
`<MAC_USER>`, `<DEVEL_ROOT>`, `<REPO_ROOT>`).

The real values live in **`canon/local/`**, which is `.gitignore`d and
must never be committed. `canon/local.example/` (this folder) is the
committed template.

> The parent repo went **private** on 2026-09-25, but this split stays: the
> overlay is still its own private repo (`<GITHUB_USER>/llm-lammps-local`) and the
> parent stays placeholder-only. Reason: one leak-proof boundary is easier to
> reason about than "private, so anything goes", and it keeps a public
> framework-only split possible.

## Setup

**First machine (creating the overlay):**

```
cp -R <REPO_ROOT>/canon/local.example <REPO_ROOT>/canon/local
cd <REPO_ROOT>/canon/local
mv gitignore.example .gitignore
mv this-machine.example .this-machine     # then edit to name THIS machine
$EDITOR local.yaml
$EDITOR clusters.local.yaml
```

**Every later machine:** clone the private overlay repo (below), then
write `.this-machine` by hand — it is the one file that must differ per
machine and is excluded from sync.

```
git clone <PRIVATE_OVERLAY_REPO> <REPO_ROOT>/canon/local
echo M2 > <REPO_ROOT>/canon/local/.this-machine
```

`.this-machine` exists because a session cannot work out which Mac it is
attached to: a Cowork shell runs in an isolated Linux VM, so `hostname`
returns the VM's name, not the Mac's. Verified 2026-07-28.

The session-startup ritual checks for `canon/local/local.yaml` at step 0
and refuses cluster work without it.

## What lives here

```
local.yaml               machine map + local roots
clusters.local.yaml      real ssh user/host/scratch per cluster, notify email
.this-machine            one line: which Mac this checkout is on (NOT synced)
.gitignore               excludes .this-machine from the overlay repo
reference/               free-text cluster notes and config dumps too
                         machine-specific or too personal for the public repo
```

## How the pilot uses it

- `canon/clusters.yaml` stays the **structure** (partitions, modules,
  sshfs options, scratch policy) — public, committed, placeholder-only.
- `canon/local/clusters.local.yaml` supplies the **substitutions** for
  the placeholders in that file.
- `canon/local/local.yaml` supplies the machine map and the local roots
  (`DEVEL_ROOT`, simulations root, admin-projects root, mount root).

The pilot reads both and resolves placeholders before writing any
submit script, sshfs command, or path into a project file.

## Keeping it in step across machines

`canon/local/` is a few kB of text on two or more Macs. Two supported
mechanisms — pick one and stick to it:

**(a) Private git repo — recommended.** Matches the workspace rule
"code / dev projects: GitHub is authoritative", and gives you history
and conflict detection:

```
# once, on the first machine
cd <REPO_ROOT>/canon/local
git init && git add -A
git commit -m "local identity overlay"
gh repo create __GH__/llm-lammps-local --private --source=. --push

# on every other machine
git clone git@github.com:__GH__/llm-lammps-local.git <REPO_ROOT>/canon/local
```

`canon/local/` is gitignored by the parent repo, so a nested checkout is
invisible to it — no submodule wiring needed, and nothing can leak into
the public history.

**(b) iCloud Drive + symlink.** Only if you would rather not have a
second repo. This is config text, well under the ~1 GB iCloud pain
threshold, so it does not violate the "keep research projects out of
iCloud" rule:

```
mkdir -p ~/Library/Mobile\ Documents/com~apple~CloudDocs/llm-lammps-local
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/llm-lammps-local \
      <REPO_ROOT>/canon/local
```

Trade-off: no history, and iCloud can serve a stale copy right after an
edit on the other machine. Check `local.yaml`'s `updated:` stamp if a
value looks wrong.

**Do not** sync this folder by rsync-from-memory or by hand-copying —
that is how the two machines silently diverge.

## Before every push

```
python3 <REPO_ROOT>/canon/templates/lint-no-identity.py
```

It fails if any tracked file contains a real username, hostname, email
or home path. Wire it as a pre-push hook if you want it enforced.
