#!/usr/bin/env python3
"""lint-no-identity.py — guard the scrub boundary of the public repo.

erik (LLM-LAMMPS designer), 2026-07-28.

This repo is public. Real cluster usernames, hostnames, notification
addresses and local home paths live ONLY in canon/local/, which is
.gitignore'd. This lint fails if any TRACKED file contains one of them.

Two checks:
  (1) Literal — every YAML *value* in canon/local/ that differs from the
      canon/local.example/ template is grepped for verbatim across tracked
      files. The strong check: it catches your actual identity, whatever
      it looks like.
  (2) Pattern — generic shapes that should never appear in a scrubbed file
      (emails, /Users/<name>, ssh user@host, MPG/MPCDF hostnames, real
      scratch paths), so the lint still bites on a fresh clone that has no
      canon/local/ yet.

Run before every push. Exit 0 = clean, 1 = would leak, 2 = cannot run.

Python, not bash, on purpose: macOS ships bash 3.2 and BSD grep, which
have neither `grep -P` nor reliable `case` inside `$(...)`. A lint that
only runs on one machine is not a guard. (Lesson: the shell style guide
applies to *cluster* scripts, where the interpreter is known; local
tooling that must run on every Mac gets Python.)

Implements "fix the class, not the instance" (canon/learnings.md
"Process"): hand-scrubbing before each push is the instance; this is the
class.
"""

import os
import re
import subprocess
import sys

# Tokens that are deliberate, not identity.
SAFE = re.compile(
    r"<[A-Z_]+>"
    r"|\$USER|\$\{USER\}|\$HOME"
    r"|example\.(com|edu)"
    r"|user@host|git@github\.com|@github\.com"
    r"|<you>|<user>|<name>"
    r"|mycluster\.edu|login\.mycluster"
)

# Whole lines that are allowed to carry a match.
LINE_ALLOW = re.compile(r"github\.com|docs\.mpcdf\.mpg\.de|www\.mpcdf\.mpg\.de")

PATTERNS = [
    ("email",         re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
    ("mac home",      re.compile(r"/Users/[A-Za-z0-9._-]+")),
    ("cluster home",  re.compile(r"/home/[A-Za-z0-9._-]+")),
    ("ssh user@host", re.compile(r"ssh\s+[A-Za-z0-9._-]+@[A-Za-z0-9.-]+")),
    ("MPG host",      re.compile(r"[a-z0-9-]+\.(rzg|mpcdf|bc)\.(mpg\.)?(de|mpg\.de)")),
    ("scratch path",  re.compile(r"/(?:cmmc/)?ptmp/(?!\$|<)[a-z][a-z0-9]*")),
    ("/u/ path",      re.compile(r"/u/(?!\$|<)[a-z][a-z0-9]*")),
]

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
YAML_KV = re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_-]*:\s+(.+)$")


def repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def tracked_files(root):
    try:
        out = subprocess.run(
            ["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("lint-no-identity: not a git work tree (%s)" % root, file=sys.stderr)
        sys.exit(2)
    return [f for f in out.splitlines() if f]


def local_values(root):
    """YAML values in canon/local/ that differ from the committed template."""
    local_dir = os.path.join(root, "canon", "local")
    if not os.path.isdir(local_dir):
        return None
    values = set()
    for name in sorted(os.listdir(local_dir)):
        if not name.endswith((".yaml", ".yml")):
            continue          # README.md and friends are prose, not config
        path = os.path.join(local_dir, name)
        example = os.path.join(root, "canon", "local.example", name)
        template = ""
        if os.path.isfile(example):
            template = read(example)
        for line in read(path).splitlines():
            line = line.split("#", 1)[0].rstrip()
            m = YAML_KV.match(line)
            if not m:
                continue
            v = m.group(1).strip().strip("'\"")
            if len(v) < 5 or "<" in v or ISO_DATE.match(v):
                continue
            if v in template:      # unchanged placeholder text is not identity
                continue
            values.add(v)
    return values


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main():
    root = repo_root()
    os.chdir(root)
    findings = []

    # canon/local/ is the private overlay: real values BELONG there.
    # .github/ carries the user's own author byline and institutional address on
    # workflows he publishes deliberately, and `deploy/rollout.sh` on M5
    # REGENERATES those files -- scrubbing them by hand would be undone on the
    # next rollout. This linter guards CLUSTER identity (user, host, scratch,
    # Mac home), not authorship of a public repo. (Added 2026-08-26, after the
    # repo-vitals workflow arrived from PR #1 carrying a byline email.)
    SKIP_PREFIXES = ("canon/local/", ".github/")
    files = [
        f for f in tracked_files(root)
        if not f.startswith(SKIP_PREFIXES)
    ]

    # ---- (1) literal check ------------------------------------------------
    values = local_values(root)
    if values is None:
        print("lint-no-identity: NOTE canon/local/ absent — literal check skipped.")
        values = set()

    for f in files:
        if not os.path.isfile(f):
            continue
        lines = read(f).splitlines()
        for n, line in enumerate(lines, 1):
            if LINE_ALLOW.search(line):
                continue
            for v in values:
                if v in line:
                    findings.append((f, n, "literal from canon/local/: %s" % v))

    # ---- (2) pattern check ------------------------------------------------
    for f in files:
        if f.startswith("canon/local.example/") or not os.path.isfile(f):
            continue
        lines = read(f).splitlines()
        for n, line in enumerate(lines, 1):
            if LINE_ALLOW.search(line):
                continue
            for label, pat in PATTERNS:
                for m in pat.finditer(line):
                    tok = m.group(0)
                    if SAFE.search(tok):
                        continue
                    findings.append((f, n, "%s: %s" % (label, tok)))

    if not findings:
        print("lint-no-identity: clean — no identity in tracked files.")
        return 0

    seen = set()
    for f, n, what in sorted(findings):
        key = (f, n, what)
        if key in seen:
            continue
        seen.add(key)
        print("  LEAK  %s:%d  %s" % (f, n, what))
    print("")
    print("lint-no-identity: FAILED. Move the values above into canon/local/")
    print("and leave a <PLACEHOLDER> in the tracked file. Do not push.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
