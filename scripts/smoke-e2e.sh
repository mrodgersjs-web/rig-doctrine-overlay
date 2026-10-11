#!/usr/bin/env bash
# scripts/smoke-e2e.sh - overlay a fresh copy of the sample repo end to end.
#
#   1. copy tests/fixtures/sample-repo to a temp dir and commit it
#   2. apply-overlay.sh, then .rig/verify.sh must pass all 8 layers
#   3. plant three violations (done-claim without evidence, untested module,
#      secret-shaped string); rig_checks.py must report all three and verify.sh must fail
#   4. remove the planted files, uninstall-overlay.sh, and diff against a
#      pristine copy: the target must be unchanged
#
# Usage: scripts/smoke-e2e.sh        (exit 0 = every step behaved as expected)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
T="$WORK/sample-repo"

say() { printf '\n== %s\n' "$*"; }
die() { printf 'SMOKE FAIL: %s\n' "$*" >&2; exit 1; }

say "1. fresh sample repo"
cp -R "$ROOT/tests/fixtures/sample-repo" "$T"
git -C "$T" init -q
git -C "$T" add -A
git -C "$T" -c user.name=smoke -c user.email=smoke@example.invalid commit -q -m initial
cp -R "$T" "$WORK/pristine"

say "2. apply + verify (expect PASS)"
"$ROOT/apply-overlay.sh" "$T"
(cd "$T" && .rig/verify.sh) || die "verify.sh failed on a clean overlaid repo"

say "3. plant violations (expect FAIL x3)"
printf '%s\n' '{"id": "smoke-1", "status": "done", "claim": "everything works"}' >> "$T/.rig/claims.jsonl"
printf 'def median(xs):\n    return sorted(xs)[len(xs) // 2]\n' > "$T/calc/stats.py"
printf 'AWS_KEY_ID = "%s"\n' "AKIA$(printf 'Q7XZ%.0s' 1 2 3 4)" > "$T/calc/settings.py"
set +e
out="$(cd "$T" && python3 .rig/rig_checks.py all)"
rc=$?
set -e
printf '%s\n' "$out"
[ "$rc" -eq 1 ] || die "rig_checks.py exit $rc, expected 1"
grep -q "claim 'smoke-1': done-claim has no evidence" <<<"$out" || die "done-claim violation not reported"
grep -q "calc/stats.py .*no test file" <<<"$out" || die "missing-test violation not reported"
grep -q "calc/settings.py:1 .*AWS access key id" <<<"$out" || die "secret violation not reported"
if (cd "$T" && .rig/verify.sh --continue >/dev/null); then die "verify.sh passed with planted violations"; fi
echo "verify.sh failed as expected"

say "4. clean up + uninstall (expect target unchanged)"
rm -f "$T/calc/stats.py" "$T/calc/settings.py"
"$ROOT/uninstall-overlay.sh" "$T"
find "$T" -name __pycache__ -prune -exec rm -rf {} + ; rm -rf "$T/.pytest_cache"
diff -r -x .git "$WORK/pristine" "$T" || die "target differs from pristine copy after uninstall"
[ -z "$(git -C "$T" status --porcelain)" ] || die "git status not clean after uninstall"

say "SMOKE PASS: apply -> verify -> 3 violations caught -> uninstall left target unchanged"
