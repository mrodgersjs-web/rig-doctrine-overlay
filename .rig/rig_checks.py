#!/usr/bin/env python3
"""rig_checks.py - doctrine checks installed by rig-doctrine-overlay.

Standard library only, so it runs in any repo that has python3 >= 3.8.

Checks:
  claims   every "done" claim in .rig/claims.jsonl must bind to evidence:
           an existing non-empty file (optionally sha256-pinned) or a
           command plus its non-empty output. Prose is not evidence.
  tests    every changed source module must have a matching test file.
  secrets  no secret-shaped strings (cloud keys, tokens, private keys,
           hard-coded credentials) in the repo's files.
  all      run the three checks above.

Usage:
  python3 .rig/rig_checks.py all [--root DIR] [--base GIT_REF] [--json]
  python3 .rig/rig_checks.py claims|tests|secrets [--root DIR] ...

Exit codes: 0 no violations, 1 one or more violations, 2 usage error.
A line containing "rig: allow-secret" is skipped by the secrets check.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import math
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

DONE_STATUSES = {"done", "complete", "completed", "verified", "shipped"}
SKIP_DIRS = {".git", ".rig", ".venv", "venv", "node_modules", "dist", "build", "__pycache__", ".tox"}
SOURCE_EXTS = {".py", ".js", ".jsx", ".ts", ".tsx", ".go"}
NON_MODULE_NAMES = {"__init__.py", "__main__.py", "conftest.py", "setup.py", "noxfile.py", "manage.py"}
TEST_DIR_NAMES = {"tests", "test", "__tests__", "spec", "fixtures", "testdata", "docs", "examples"}
MAX_SCAN_BYTES = 1_000_000
ALLOW_MARKER = "rig: allow-secret"


@dataclass
class Violation:
    check: str
    path: str
    line: int
    message: str

    def render(self) -> str:
        loc = f"{self.path}:{self.line}" if self.line else self.path
        return f"VIOLATION {self.check:<8} {loc}  {self.message}"


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


def _git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=False)


def is_git_repo(root: Path) -> bool:
    try:
        return _git(root, "rev-parse", "--is-inside-work-tree").stdout.strip() == "true"
    except FileNotFoundError:
        return False


def _skipped(rel: str) -> bool:
    return any(part in SKIP_DIRS for part in Path(rel).parts)


def list_files(root: Path) -> list[str]:
    """Repo files as POSIX relative paths (git-tracked + untracked-not-ignored if git)."""
    if is_git_repo(root):
        out = _git(root, "ls-files", "-co", "--exclude-standard").stdout.splitlines()
        files = [f for f in out if f and (root / f).is_file()]
    else:
        files = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for name in filenames:
                files.append((Path(dirpath) / name).relative_to(root).as_posix())
    return sorted({f for f in files if not _skipped(f)})


def changed_files(root: Path, base: str | None) -> list[str]:
    """Files changed vs `base` (default HEAD) plus untracked files.

    Outside git, or in a repo without commits, every file counts as changed.
    """
    if not is_git_repo(root):
        return list_files(root)
    ref = base or "HEAD"
    if _git(root, "rev-parse", "--verify", "--quiet", ref + "^{commit}").returncode != 0:
        if base:
            raise SystemExit(f"error: base ref not found: {base}")
        return list_files(root)
    diff = _git(root, "diff", "--name-only", "--diff-filter=ACMR", ref).stdout.splitlines()
    untracked = _git(root, "ls-files", "--others", "--exclude-standard").stdout.splitlines()
    return sorted({f for f in diff + untracked if f and not _skipped(f) and (root / f).is_file()})


# --------------------------------------------------------------------------
# check 1: done-claims need evidence
# --------------------------------------------------------------------------


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _check_evidence(root: Path, ev: object) -> str | None:
    """Return a problem description, or None if the evidence binds."""
    if ev is None or ev == "" or ev == {} or ev == []:
        return "done-claim has no evidence"
    if isinstance(ev, list):
        problems = [p for p in (_check_evidence(root, e) for e in ev) if p]
        return problems[0] if problems else None
    if isinstance(ev, str):
        ev = {"path": ev}
    if not isinstance(ev, dict):
        return f"evidence has unsupported type {type(ev).__name__}"
    if "path" in ev:
        target = (root / str(ev["path"])).resolve()
        try:
            target.relative_to(root.resolve())
        except ValueError:
            return f"evidence path escapes the repo: {ev['path']}"
        if not target.is_file():
            return f"evidence is not an existing file (prose is not evidence): {ev['path']!r}"
        if target.stat().st_size == 0:
            return f"evidence file is empty: {ev['path']}"
        want = ev.get("sha256")
        if want and _sha256(target) != str(want).lower():
            return f"evidence file changed since the claim (sha256 mismatch): {ev['path']}"
        return None
    if "command" in ev:
        if not str(ev.get("command", "")).strip():
            return "evidence command is empty"
        if not str(ev.get("output", "")).strip():
            return "evidence names a command but records no output"
        return None
    return "evidence needs a 'path' or a 'command' + 'output'"


def check_claims(root: Path, ledger: str = ".rig/claims.jsonl") -> list[Violation]:
    path = root / ledger
    if not path.is_file():
        return []
    out: list[Violation] = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError as exc:
            out.append(Violation("claims", ledger, n, f"line is not valid JSON ({exc.msg})"))
            continue
        if not isinstance(rec, dict):
            out.append(Violation("claims", ledger, n, "claim must be a JSON object"))
            continue
        cid = rec.get("id") or f"line {n}"
        if str(rec.get("status", "")).lower() not in DONE_STATUSES:
            continue
        problem = _check_evidence(root, rec.get("evidence"))
        if problem:
            out.append(Violation("claims", ledger, n, f"claim {cid!r}: {problem}"))
    return out


# --------------------------------------------------------------------------
# check 2: changed modules need tests
# --------------------------------------------------------------------------


def is_test_file(rel: str) -> bool:
    p = Path(rel)
    name = p.name
    return (
        name.startswith("test_")
        or p.stem.endswith("_test")
        or ".test." in name
        or ".spec." in name
        or any(part in {"tests", "test", "__tests__"} for part in p.parts[:-1])
    )


def needs_test(rel: str, exempt: list[str]) -> bool:
    p = Path(rel)
    if p.suffix not in SOURCE_EXTS or p.name in NON_MODULE_NAMES or is_test_file(rel):
        return False
    if any(part in TEST_DIR_NAMES for part in p.parts[:-1]):
        return False
    if re.search(r"\.(config|conf|d)\.[jt]sx?$", p.name):
        return False
    return not any(fnmatch.fnmatch(rel, pat) for pat in exempt)


def test_candidates(rel: str) -> set[str]:
    p = Path(rel)
    stem = p.stem
    if p.suffix == ".py":
        return {f"test_{stem}.py", f"{stem}_test.py"}
    if p.suffix == ".go":
        return {f"{stem}_test.go"}
    return {f"{stem}.{kind}.{ext}" for kind in ("test", "spec") for ext in ("js", "jsx", "ts", "tsx", "mjs", "cjs")}


def _read_exempt(root: Path) -> list[str]:
    f = root / ".rig" / "test-exempt.txt"
    if not f.is_file():
        return []
    return [ln.strip() for ln in f.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")]


def check_tests(root: Path, base: str | None = None) -> list[Violation]:
    exempt = _read_exempt(root)
    all_files = list_files(root)
    test_names: dict[str, list[str]] = {}
    for f in all_files:
        if is_test_file(f) or f.endswith("_test.go"):
            test_names.setdefault(Path(f).name, []).append(f)
    out: list[Violation] = []
    for rel in changed_files(root, base):
        if not needs_test(rel, exempt):
            continue
        cands = test_candidates(rel)
        found = [t for c in cands for t in test_names.get(c, [])]
        if rel.endswith(".go"):  # Go tests must sit next to the module
            found = [t for t in found if Path(t).parent == Path(rel).parent]
        if not found:
            want = " or ".join(sorted(cands)[:2])
            out.append(Violation("tests", rel, 0, f"changed module has no test file (expected {want})"))
    return out


# --------------------------------------------------------------------------
# check 3: secret-shaped strings
# --------------------------------------------------------------------------

SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("AWS access key id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})\b")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("API secret key (sk-)", re.compile(r"\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{24,}")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("private key block", re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY-----")),
]
ASSIGNMENT = re.compile(
    r"""(?ix)
    \b[\w.-]*(?:api[_-]?key|secret|token|passwd|password|access[_-]?key)[\w.-]*
    ["']?\s*[:=]\s*["']([^"'\s]{16,})["']
    """
)
PLACEHOLDER = re.compile(r"[<>${}]|example|changeme|placeholder|dummy|x{6,}|\*{4,}", re.I)


def _entropy(s: str) -> float:
    counts = {c: s.count(c) for c in set(s)}
    return -sum(n / len(s) * math.log2(n / len(s)) for n in counts.values())


def mask(s: str) -> str:
    return s[:4] + "..." + f"({len(s)} chars)"


def scan_text(text: str) -> list[tuple[int, str, str]]:
    """Return (line_no, kind, masked_value) for each secret-shaped string."""
    hits = []
    for n, line in enumerate(text.splitlines(), start=1):
        if ALLOW_MARKER in line:
            continue
        found = False
        for kind, pat in SECRET_PATTERNS:
            m = pat.search(line)
            if m:
                hits.append((n, kind, mask(m.group(0))))
                found = True
                break
        if found:
            continue
        m = ASSIGNMENT.search(line)
        if m:
            val = m.group(1)
            if not PLACEHOLDER.search(val) and _entropy(val) >= 3.0:
                hits.append((n, "hard-coded credential", mask(val)))
    return hits


def check_secrets(root: Path) -> list[Violation]:
    out: list[Violation] = []
    for rel in list_files(root):
        f = root / rel
        try:
            if f.stat().st_size > MAX_SCAN_BYTES:
                continue
            data = f.read_bytes()
        except OSError:
            continue
        if b"\0" in data[:8192]:
            continue
        for n, kind, masked in scan_text(data.decode("utf-8", errors="replace")):
            out.append(Violation("secrets", rel, n, f"{kind} found: {masked}"))
    return out


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def run(check: str, root: Path, base: str | None) -> list[Violation]:
    checks = ["claims", "tests", "secrets"] if check == "all" else [check]
    out: list[Violation] = []
    for c in checks:
        if c == "claims":
            out += check_claims(root)
        elif c == "tests":
            out += check_tests(root, base)
        elif c == "secrets":
            out += check_secrets(root)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="rig_checks.py", description="RIG doctrine checks")
    ap.add_argument("check", choices=["all", "claims", "tests", "secrets"])
    ap.add_argument("--root", default=None, help="repo root (default: parent of .rig/ or cwd)")
    ap.add_argument(
        "--base",
        default=os.environ.get("RIG_BASE_REF") or None,
        help="git ref to diff against for the tests check (default: HEAD, or $RIG_BASE_REF)",
    )
    ap.add_argument("--json", action="store_true", help="print violations as JSON")
    args = ap.parse_args(argv)

    if args.root:
        root = Path(args.root).resolve()
    else:
        here = Path(__file__).resolve().parent
        root = here.parent if here.name == ".rig" else Path.cwd()
    if not root.is_dir():
        print(f"error: root is not a directory: {root}", file=sys.stderr)
        return 2

    violations = run(args.check, root, args.base)
    if args.json:
        print(json.dumps({"root": str(root), "check": args.check, "violations": [asdict(v) for v in violations]}, indent=2))
    else:
        for v in violations:
            print(v.render())
        label = args.check if args.check != "all" else "claims+tests+secrets"
        if violations:
            print(f"rig_checks {label}: FAIL ({len(violations)} violation(s))")
        else:
            print(f"rig_checks {label}: PASS (0 violations)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
