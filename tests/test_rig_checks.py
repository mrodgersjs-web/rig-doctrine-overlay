"""Unit tests for templates/rig_checks.py (no git needed)."""

import hashlib
import importlib.util
import json
import sys

from conftest import ROOT

_spec = importlib.util.spec_from_file_location("rig_checks", ROOT / "templates" / "rig_checks.py")
rc = importlib.util.module_from_spec(_spec)
sys.modules["rig_checks"] = rc
_spec.loader.exec_module(rc)


def _ledger(tmp_path, *records):
    (tmp_path / ".rig").mkdir(exist_ok=True)
    (tmp_path / ".rig" / "claims.jsonl").write_text("".join(json.dumps(r) + "\n" for r in records))


def test_claims_open_items_need_no_evidence(tmp_path):
    _ledger(tmp_path, {"id": "a", "status": "in_progress"})
    assert rc.check_claims(tmp_path) == []


def test_claims_file_evidence_with_sha(tmp_path):
    (tmp_path / "proof.txt").write_text("3 passed\n")
    sha = hashlib.sha256(b"3 passed\n").hexdigest()
    _ledger(tmp_path, {"id": "a", "status": "done", "evidence": {"path": "proof.txt", "sha256": sha}})
    assert rc.check_claims(tmp_path) == []
    (tmp_path / "proof.txt").write_text("1 failed\n")
    [v] = rc.check_claims(tmp_path)
    assert "sha256 mismatch" in v.message


def test_claims_bad_evidence_shapes(tmp_path):
    (tmp_path / "empty.txt").write_text("")
    _ledger(
        tmp_path,
        {"id": "a", "status": "done", "evidence": {"path": "empty.txt"}},
        {"id": "b", "status": "verified", "evidence": {"command": "pytest", "output": ""}},
        {"id": "c", "status": "done", "evidence": {"path": "../outside.txt"}},
    )
    (tmp_path / ".rig" / "claims.jsonl").open("a").write("{not json\n")
    msgs = [v.message for v in rc.check_claims(tmp_path)]
    assert any("evidence file is empty" in m for m in msgs)
    assert any("records no output" in m for m in msgs)
    assert any("escapes the repo" in m for m in msgs)
    assert any("not valid JSON" in m for m in msgs)


def test_tests_check_without_git_treats_all_as_changed(tmp_path):
    (tmp_path / "pkg").mkdir()
    (tmp_path / "pkg" / "__init__.py").write_text("")
    (tmp_path / "pkg" / "a.py").write_text("x = 1\n")
    (tmp_path / "web.ts").write_text("export const y = 1\n")
    (tmp_path / "web.test.ts").write_text("test('y', () => {})\n")
    (tmp_path / "jest.config.js").write_text("module.exports = {}\n")
    paths = [v.path for v in rc.check_tests(tmp_path)]
    assert paths == ["pkg/a.py"]


def test_tests_exempt_file(tmp_path):
    (tmp_path / "scripts").mkdir()
    (tmp_path / "scripts" / "gen.py").write_text("print(1)\n")
    (tmp_path / ".rig").mkdir()
    (tmp_path / ".rig" / "test-exempt.txt").write_text("scripts/*\n")
    assert rc.check_tests(tmp_path) == []


def test_go_test_must_sit_next_to_module(tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    (tmp_path / "a" / "util.go").write_text("package a\n")
    (tmp_path / "b" / "util_test.go").write_text("package b\n")
    assert [v.path for v in rc.check_tests(tmp_path)] == ["a/util.go"]
    (tmp_path / "a" / "util_test.go").write_text("package a\n")
    assert rc.check_tests(tmp_path) == []


def test_secret_patterns_and_false_positives():
    pk = "-----BEGIN RSA " + "PRIVATE KEY-----"
    hits = rc.scan_text(
        "\n".join(
            [
                "key = 'sk-" + "Zr8sT2qLm9Xw4Vb7Nc1Kp6Hd" + "'",
                pk,
                'password = "' + "q8F!z2Lr#9wPx4Tm" + '"',
                'password = "<REPLACE: your password>"',
                "api_key = os.environ['API_KEY']",
                'token = "aaaaaaaaaaaaaaaaaaaa"',
                "AKIA" + "Q7XZ" * 4 + "  # rig: allow-secret",
            ]
        )
    )
    assert [(n, kind) for n, kind, _ in hits] == [
        (1, "API secret key (sk-)"),
        (2, "private key block"),
        (3, "hard-coded credential"),
    ]


def test_secrets_skips_binary_and_rig_dir(tmp_path):
    (tmp_path / "blob.bin").write_bytes(b"\0\1AKIA" + b"Q7XZ" * 4)
    (tmp_path / ".rig").mkdir()
    (tmp_path / ".rig" / "x.txt").write_text("AKIA" + "Q7XZ" * 4)
    assert rc.check_secrets(tmp_path) == []


def test_cli_exit_codes(tmp_path, capsys):
    assert rc.main(["secrets", "--root", str(tmp_path)]) == 0
    (tmp_path / "creds.txt").write_text("AKIA" + "Q7XZ" * 4 + "\n")
    assert rc.main(["secrets", "--root", str(tmp_path)]) == 1
    out = capsys.readouterr().out
    assert "creds.txt:1" in out and "FAIL (1 violation(s))" in out


def test_repo_dogfood_copies_match_templates():
    for name in ("smoke.sh", "verify.sh", "rig_checks.py"):
        assert (ROOT / ".rig" / name).read_bytes() == (ROOT / "templates" / name).read_bytes(), name
