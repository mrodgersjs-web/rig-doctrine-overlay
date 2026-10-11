import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "tests" / "fixtures" / "sample-repo"
APPLY = ROOT / "apply-overlay.sh"
UNINSTALL = ROOT / "uninstall-overlay.sh"

GIT_ENV = {
    "GIT_AUTHOR_NAME": "test",
    "GIT_AUTHOR_EMAIL": "test@example.invalid",
    "GIT_COMMITTER_NAME": "test",
    "GIT_COMMITTER_EMAIL": "test@example.invalid",
}


def run(cmd, cwd=None, env_extra=None):
    env = dict(os.environ, **GIT_ENV)
    # make sure the venv's python/pytest are what the installed scripts see
    env["PATH"] = str(Path(sys.executable).parent) + os.pathsep + env.get("PATH", "")
    env.pop("RIG_BASE_REF", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, capture_output=True, text=True, check=False)


def tree_snapshot(root: Path) -> dict:
    """Map of relative path -> (sha256, mode) for every file and dir outside .git."""
    snap = {}
    for p in sorted(root.rglob("*")):
        rel = p.relative_to(root).as_posix()
        if rel == ".git" or rel.startswith(".git/") or "__pycache__" in rel or ".pytest_cache" in rel:
            continue
        if p.is_dir():
            snap[rel + "/"] = ("dir", p.stat().st_mode & 0o777)
        else:
            snap[rel] = (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mode & 0o777)
    return snap


@pytest.fixture
def sample_repo(tmp_path):
    """A fresh committed git copy of the fixture sample repo."""
    repo = tmp_path / "sample-repo"
    shutil.copytree(FIXTURE, repo)
    assert run(["git", "init", "-q"], cwd=repo).returncode == 0
    run(["git", "add", "-A"], cwd=repo)
    r = run(["git", "commit", "-q", "-m", "initial"], cwd=repo)
    assert r.returncode == 0, r.stderr
    return repo


@pytest.fixture
def overlaid(sample_repo):
    r = run([APPLY, sample_repo])
    assert r.returncode == 0, r.stdout + r.stderr
    return sample_repo
