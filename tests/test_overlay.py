"""End-to-end tests: apply, verify (pass + each violation), uninstall."""

import json
import shutil

from conftest import APPLY, UNINSTALL, run, tree_snapshot

CHECKS = ".rig/rig_checks.py"

# Secret-shaped strings are assembled at runtime so this file itself
# never contains one (the repo's own CI runs the secrets check on itself).
FAKE_AWS_KEY = "AKIA" + "Q7XZ" * 4
FAKE_GH_TOKEN = "ghp_" + "a1B2c3D4e5" * 4


# ---------------------------------------------------------------- apply


def test_apply_installs_every_layer(overlaid):
    for rel in [
        "AGENTS.md",
        "CLAUDE.md",
        ".rig/smoke.sh",
        ".rig/verify.sh",
        ".rig/rig_checks.py",
        ".rig/proof-gate.yml",
        ".rig/claims.jsonl",
        ".rig/failures.json",
        ".rig/overlay/manifest.tsv",
        "spec/features/example.feature",
    ]:
        assert (overlaid / rel).is_file(), rel
    readme = (overlaid / "README.md").read_text()
    assert readme.startswith("<!-- ====")
    assert "FDE STANDARD HEADER" in readme
    assert readme.rstrip().endswith("used as the overlay target in rig-doctrine-overlay's tests.")
    gate = (overlaid / ".rig/proof-gate.yml").read_text()
    assert 'name: "sample-repo"' in gate
    manifest = (overlaid / ".rig/overlay/manifest.tsv").read_text().splitlines()
    assert "modified\tREADME.md" in manifest
    assert "created\tAGENTS.md" in manifest
    assert "dir\tspec" in manifest and "dir\tspec/features" in manifest
    assert (overlaid / ".rig/overlay/backup/README.md").read_text().startswith("# calc")


def test_apply_refuses_second_install_without_force(overlaid):
    r = run([APPLY, overlaid])
    assert r.returncode == 2
    assert "already has the overlay" in r.stderr


def test_force_reinstall_keeps_single_header_and_original_backup(overlaid):
    r = run([APPLY, overlaid, "--force"])
    assert r.returncode == 0, r.stderr
    assert (overlaid / "README.md").read_text().count("FDE STANDARD HEADER — installed") == 1
    assert (overlaid / ".rig/overlay/backup/README.md").read_text().startswith("# calc")


def test_apply_refuses_foreign_rig_dir(sample_repo):
    (sample_repo / ".rig").mkdir()
    (sample_repo / ".rig" / "mine.txt").write_text("not the overlay's\n")
    r = run([APPLY, sample_repo, "--force"])
    assert r.returncode == 2
    assert (sample_repo / ".rig" / "mine.txt").read_text() == "not the overlay's\n"


def test_dry_run_writes_nothing(sample_repo):
    before = tree_snapshot(sample_repo)
    r = run([APPLY, sample_repo, "--dry-run"])
    assert r.returncode == 0, r.stderr
    assert "[dry-run] would write: AGENTS.md" in r.stdout
    assert tree_snapshot(sample_repo) == before


def test_apply_preserves_existing_agents_md(sample_repo):
    (sample_repo / "AGENTS.md").write_text("# our own rules\n")
    assert run([APPLY, sample_repo]).returncode == 0
    assert (sample_repo / "AGENTS.md").read_text() == "# our own rules\n"


# ---------------------------------------------------------------- verify: pass


def test_checks_pass_on_clean_overlaid_repo(overlaid):
    r = run(["python3", CHECKS, "all"], cwd=overlaid)
    assert r.returncode == 0, r.stdout
    assert "rig_checks claims+tests+secrets: PASS (0 violations)" in r.stdout


def test_verify_all_layers_pass(overlaid):
    r = run([overlaid / ".rig/verify.sh", "--continue"], cwd=overlaid)
    assert r.returncode == 0, r.stdout
    assert "ALL 8 LAYERS: PASS" in r.stdout
    assert "L2-unit" in r.stdout and "pytest exited 0" in r.stdout
    assert "L5-doctrine" in r.stdout


def test_smoke_passes(overlaid):
    r = run([overlaid / ".rig/smoke.sh"], cwd=overlaid)
    assert r.returncode == 0, r.stdout
    assert "SMOKE RESULT:" in r.stdout and "PASS" in r.stdout


def test_done_claim_with_command_evidence_passes(overlaid):
    rec = {"id": "c1", "status": "done", "claim": "mean handles empty input", "evidence": {"command": "pytest -q", "output": "3 passed"}}
    (overlaid / ".rig/claims.jsonl").write_text(json.dumps(rec) + "\n")
    r = run(["python3", CHECKS, "claims"], cwd=overlaid)
    assert r.returncode == 0, r.stdout


# ---------------------------------------------------------------- verify: violations


def test_violation_done_claim_without_evidence(overlaid):
    rec = {"id": "c2", "status": "done", "claim": "all tests pass"}
    (overlaid / ".rig/claims.jsonl").write_text(json.dumps(rec) + "\n")
    r = run(["python3", CHECKS, "claims"], cwd=overlaid)
    assert r.returncode == 1
    assert "claim 'c2': done-claim has no evidence" in r.stdout
    v = run([overlaid / ".rig/verify.sh", "--continue"], cwd=overlaid)
    assert v.returncode == 1
    assert "FAIL" in v.stdout and "L5-doctrine" in v.stdout and "VERIFICATION FAILED" in v.stdout


def test_violation_done_claim_with_prose_evidence(overlaid):
    rec = {"id": "c3", "status": "done", "evidence": "I ran it and it worked"}
    (overlaid / ".rig/claims.jsonl").write_text(json.dumps(rec) + "\n")
    r = run(["python3", CHECKS, "claims"], cwd=overlaid)
    assert r.returncode == 1
    assert "prose is not evidence" in r.stdout


def test_violation_missing_test_for_changed_module(overlaid):
    (overlaid / "calc" / "stats.py").write_text("def median(xs):\n    return sorted(xs)[len(xs) // 2]\n")
    r = run(["python3", CHECKS, "tests"], cwd=overlaid)
    assert r.returncode == 1
    assert "calc/stats.py" in r.stdout and "no test file" in r.stdout
    # adding the test clears it
    (overlaid / "tests" / "test_stats.py").write_text(
        "from calc.stats import median\n\n\ndef test_median():\n    assert median([3, 1, 2]) == 2\n"
    )
    assert run(["python3", CHECKS, "tests"], cwd=overlaid).returncode == 0


def test_violation_secret_shaped_string(overlaid):
    (overlaid / "calc" / "settings.py").write_text(f'AWS_KEY_ID = "{FAKE_AWS_KEY}"\n')
    (overlaid / "deploy.env").write_text(f"GITHUB_TOKEN={FAKE_GH_TOKEN}\n")
    r = run(["python3", CHECKS, "secrets"], cwd=overlaid)
    assert r.returncode == 1
    assert "calc/settings.py:1" in r.stdout and "AWS access key id" in r.stdout
    assert "deploy.env:1" in r.stdout and "GitHub token" in r.stdout
    # the full secret value is never echoed
    assert FAKE_AWS_KEY not in r.stdout and FAKE_GH_TOKEN not in r.stdout


def test_all_three_violations_reported_together_as_json(overlaid):
    (overlaid / ".rig/claims.jsonl").write_text(json.dumps({"id": "c4", "status": "done"}) + "\n")
    (overlaid / "calc" / "io.py").write_text(f'token = "{FAKE_GH_TOKEN}"\n')
    r = run(["python3", CHECKS, "all", "--json"], cwd=overlaid)
    assert r.returncode == 1
    kinds = sorted({v["check"] for v in json.loads(r.stdout)["violations"]})
    assert kinds == ["claims", "secrets", "tests"]


# ---------------------------------------------------------------- uninstall


def test_uninstall_restores_target_exactly(sample_repo):
    before = tree_snapshot(sample_repo)
    assert run([APPLY, sample_repo]).returncode == 0
    assert tree_snapshot(sample_repo) != before
    r = run([UNINSTALL, sample_repo])
    assert r.returncode == 0, r.stderr
    assert tree_snapshot(sample_repo) == before
    assert run(["git", "status", "--porcelain"], cwd=sample_repo).stdout == ""


def test_uninstall_after_force_reinstall_and_verify_runs(sample_repo):
    before = tree_snapshot(sample_repo)
    assert run([APPLY, sample_repo]).returncode == 0
    assert run([sample_repo / ".rig/verify.sh"], cwd=sample_repo).returncode == 0
    assert run([APPLY, sample_repo, "--force"]).returncode == 0
    assert run([UNINSTALL, sample_repo]).returncode == 0
    assert tree_snapshot(sample_repo) == before


def test_uninstall_restores_repo_without_readme(sample_repo):
    (sample_repo / "README.md").unlink()
    before = tree_snapshot(sample_repo)
    assert run([APPLY, sample_repo]).returncode == 0
    assert (sample_repo / "README.md").is_file()
    assert run([UNINSTALL, sample_repo]).returncode == 0
    assert tree_snapshot(sample_repo) == before


def test_uninstall_restores_overwritten_agents_md(sample_repo):
    (sample_repo / "AGENTS.md").write_text("# our own rules\n")
    before = tree_snapshot(sample_repo)
    shutil.rmtree(sample_repo / ".git")  # also works outside git
    before.pop(".git/", None)
    assert run([APPLY, sample_repo, "--force"]).returncode == 0
    assert "TAC" in (sample_repo / "AGENTS.md").read_text()
    assert run([UNINSTALL, sample_repo]).returncode == 0
    assert tree_snapshot(sample_repo) == before


def test_uninstall_without_manifest_fails(sample_repo):
    r = run([UNINSTALL, sample_repo])
    assert r.returncode == 2
    assert "no overlay manifest" in r.stderr


def test_smoke_learn_records_and_replays_failures(overlaid):
    if shutil.which("jq") is None:
        import pytest

        pytest.skip("smoke.sh --learn needs jq")
    (overlaid / "spec/features/example.feature").unlink()
    r = run([overlaid / ".rig/smoke.sh", "--learn", "--gate=4"], cwd=overlaid)
    assert r.returncode == 1
    ledger = json.loads((overlaid / ".rig/failures.json").read_text())
    assert [f["gate"] for f in ledger["failures"]] == ["L4-eval"]
    r2 = run([overlaid / ".rig/smoke.sh", "--gate=4"], cwd=overlaid)
    assert "Regression replay: 1 previously-recorded failure(s)" in r2.stdout
