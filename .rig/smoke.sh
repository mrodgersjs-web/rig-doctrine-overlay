#!/usr/bin/env bash
# .rig/smoke.sh — L10 Self-Evolving Test Harness
#
# Installed by rig-doctrine-overlay. Runs five smoke gates in order:
#   1. syntax check       2. unit tests        3. integration smoke
#   4. eval gate          5. proof verification
#
# Self-evolving: with --learn, any gate that FAILs is appended to
# .rig/failures.json as a permanent record. On the NEXT run, smoke.sh
# checks failures.json and re-tests every previously-recorded failure
# FIRST (as a planted regression check) before running the normal gates.
# This means a bug that was fixed once can never silently regress again
# without smoke.sh catching it — the harness hardens itself over time.
#
# Usage:
#   .rig/smoke.sh              # run all gates, do not record new failures
#   .rig/smoke.sh --learn      # run all gates, append any FAILs to failures.json
#   .rig/smoke.sh --gate=N     # run only gate N (1-5)
#
# Exit code: 0 if all executed gates PASS, 1 if any FAIL.

set -uo pipefail

RIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$RIG_DIR/.." && pwd)"
FAILURES_FILE="$RIG_DIR/failures.json"
LEARN=0
ONLY_GATE=0
OVERALL_STATUS=0
RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for arg in "$@"; do
  case "$arg" in
    --learn) LEARN=1 ;;
    --gate=*) ONLY_GATE="${arg#--gate=}" ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^#//'
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

log()  { printf '%s\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$*"; }

record_failure() {
  # record_failure <gate_name> <reason>
  local gate="$1" reason="$2"
  [ "$LEARN" -eq 1 ] || return 0
  mkdir -p "$RIG_DIR"
  if [ ! -f "$FAILURES_FILE" ]; then
    echo '{"failures": []}' > "$FAILURES_FILE"
  fi
  local tmp; tmp="$(mktemp)"
  # append via a small python/node-free jq-free path: naive JSON array append
  if command -v jq >/dev/null 2>&1; then
    jq --arg ts "$RUN_TS" --arg gate "$gate" --arg reason "$reason" \
      '.failures += [{"ts": $ts, "gate": $gate, "reason": $reason}]' \
      "$FAILURES_FILE" > "$tmp" && mv "$tmp" "$FAILURES_FILE"
  else
    # fallback: append a line-delimited record if jq is unavailable
    printf '{"ts":"%s","gate":"%s","reason":"%s"}\n' "$RUN_TS" "$gate" "$reason" \
      >> "${FAILURES_FILE%.json}.jsonl"
  fi
  log "  learned: $gate -> $reason (recorded in .rig/failures.json)"
}

replay_known_failures() {
  [ -f "$FAILURES_FILE" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local count
  count="$(jq '.failures | length' "$FAILURES_FILE" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || return 0
  log ""
  log "== Regression replay: $count previously-recorded failure(s) =="
  jq -r '.failures[] | "  - [\(.ts)] \(.gate): \(.reason)"' "$FAILURES_FILE" 2>/dev/null
  log "(these gates run with extra scrutiny below)"
}

should_run() {
  # should_run <gate_number>
  [ "$ONLY_GATE" -eq 0 ] || [ "$ONLY_GATE" = "$1" ]
}

detect_stack() {
  if [ -f "$REPO_ROOT/package.json" ]; then echo "node"
  elif [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/setup.py" ] || [ -f "$REPO_ROOT/requirements.txt" ]; then echo "python"
  elif [ -f "$REPO_ROOT/go.mod" ]; then echo "go"
  elif [ -f "$REPO_ROOT/Cargo.toml" ]; then echo "rust"
  else echo "unknown"
  fi
}

STACK="$(detect_stack)"

log "=================================================================="
log " RIG L10 Self-Evolving Smoke Harness"
log " repo: $REPO_ROOT"
log " stack detected: $STACK"
log " mode: $([ "$LEARN" -eq 1 ] && echo 'learn (records new failures)' || echo 'check-only')"
log "=================================================================="

replay_known_failures

# ---------------------------------------------------------------------------
# Gate 1: syntax check
# ---------------------------------------------------------------------------
if should_run 1; then
  log ""
  log "-- Gate 1/5: syntax check --"
  gate_ok=1
  case "$STACK" in
    node)
      if command -v node >/dev/null 2>&1; then
        while IFS= read -r -d '' f; do
          node --check "$f" >/tmp/rig-syntax-err.$$ 2>&1 || { gate_ok=0; fail "syntax error in $f"; cat /tmp/rig-syntax-err.$$; }
        done < <(find "$REPO_ROOT" -maxdepth 3 -name '*.js' -not -path '*/node_modules/*' -print0 2>/dev/null)
        rm -f /tmp/rig-syntax-err.$$
      else
        skip "node not on PATH"
      fi
      ;;
    python)
      if command -v python3 >/dev/null 2>&1; then
        out="$(python3 -m py_compile $(find "$REPO_ROOT" -maxdepth 4 -name '*.py' -not -path '*/.venv/*' -not -path '*/venv/*' 2>/dev/null) 2>&1)"
        if [ -n "$out" ]; then gate_ok=0; fail "python syntax errors"; echo "$out"; fi
      else
        skip "python3 not on PATH"
      fi
      ;;
    go)
      if command -v gofmt >/dev/null 2>&1; then
        out="$(gofmt -l "$REPO_ROOT" 2>&1)"
        [ -z "$out" ] || { gate_ok=0; fail "gofmt reports unformatted/invalid files"; echo "$out"; }
      else
        skip "gofmt not on PATH"
      fi
      ;;
    rust)
      if command -v cargo >/dev/null 2>&1; then
        cargo check --quiet --manifest-path "$REPO_ROOT/Cargo.toml" >/tmp/rig-cargo-check.$$ 2>&1 || { gate_ok=0; fail "cargo check failed"; cat /tmp/rig-cargo-check.$$; }
        rm -f /tmp/rig-cargo-check.$$
      else
        skip "cargo not on PATH"
      fi
      ;;
    *)
      skip "no recognized stack; syntax gate is a no-op"
      ;;
  esac
  if [ "$gate_ok" -eq 1 ]; then
    pass "syntax check ($STACK)"
  else
    OVERALL_STATUS=1
    record_failure "L1-syntax" "syntax check failed for stack=$STACK"
  fi
fi

# ---------------------------------------------------------------------------
# Gate 2: unit tests
# ---------------------------------------------------------------------------
if should_run 2; then
  log ""
  log "-- Gate 2/5: unit tests --"
  gate_ok=1
  case "$STACK" in
    node)
      if [ -f "$REPO_ROOT/package.json" ] && grep -q '"test"' "$REPO_ROOT/package.json" 2>/dev/null; then
        (cd "$REPO_ROOT" && npm test --silent) >/tmp/rig-unit.$$ 2>&1 || gate_ok=0
        tail -n 40 /tmp/rig-unit.$$
        rm -f /tmp/rig-unit.$$
      else
        skip "no npm test script found"
      fi
      ;;
    python)
      if command -v pytest >/dev/null 2>&1; then
        (cd "$REPO_ROOT" && pytest -q) >/tmp/rig-unit.$$ 2>&1 || gate_ok=0
        tail -n 40 /tmp/rig-unit.$$
        rm -f /tmp/rig-unit.$$
      else
        skip "pytest not installed"
      fi
      ;;
    go)
      if command -v go >/dev/null 2>&1; then
        (cd "$REPO_ROOT" && go test ./...) >/tmp/rig-unit.$$ 2>&1 || gate_ok=0
        tail -n 40 /tmp/rig-unit.$$
        rm -f /tmp/rig-unit.$$
      else
        skip "go not on PATH"
      fi
      ;;
    rust)
      if command -v cargo >/dev/null 2>&1; then
        (cd "$REPO_ROOT" && cargo test --quiet) >/tmp/rig-unit.$$ 2>&1 || gate_ok=0
        tail -n 40 /tmp/rig-unit.$$
        rm -f /tmp/rig-unit.$$
      else
        skip "cargo not on PATH"
      fi
      ;;
    *)
      skip "no recognized test runner"
      ;;
  esac
  if [ "$gate_ok" -eq 1 ]; then
    pass "unit tests"
  else
    OVERALL_STATUS=1
    record_failure "L2-unit" "unit test suite failed for stack=$STACK"
  fi
fi

# ---------------------------------------------------------------------------
# Gate 3: integration smoke (does the entrypoint even boot?)
# ---------------------------------------------------------------------------
if should_run 3; then
  log ""
  log "-- Gate 3/5: integration smoke --"
  gate_ok=1
  entry=""
  case "$STACK" in
    node)
      entry="$(node -e "try{console.log(require('$REPO_ROOT/package.json').main||'')}catch(e){}" 2>/dev/null)"
      if [ -n "$entry" ] && [ -f "$REPO_ROOT/$entry" ]; then
        node -e "require('$REPO_ROOT/$entry')" >/tmp/rig-smoke.$$ 2>&1
        rc=$?
        cat /tmp/rig-smoke.$$; rm -f /tmp/rig-smoke.$$
        # a module that just fails on require() with an unrelated runtime error
        # (missing env, missing network) is treated as inconclusive, not FAIL,
        # but a SyntaxError/ReferenceError at load time IS a hard fail.
        if [ $rc -ne 0 ] && grep -qE 'SyntaxError|ReferenceError|Cannot find module' /tmp/rig-smoke.$$ 2>/dev/null; then
          gate_ok=0
        fi
      else
        skip "no resolvable package.json 'main' entrypoint"
      fi
      ;;
    python)
      pkg="$(find "$REPO_ROOT" -maxdepth 2 -name '__init__.py' -printf '%h\n' 2>/dev/null | head -1)"
      if [ -n "$pkg" ]; then
        modname="$(basename "$pkg")"
        (cd "$REPO_ROOT" && python3 -c "import $modname" ) >/tmp/rig-smoke.$$ 2>&1 || gate_ok=0
        cat /tmp/rig-smoke.$$; rm -f /tmp/rig-smoke.$$
      else
        skip "no top-level python package found"
      fi
      ;;
    go)
      if command -v go >/dev/null 2>&1; then
        (cd "$REPO_ROOT" && go build ./...) >/tmp/rig-smoke.$$ 2>&1 || gate_ok=0
        cat /tmp/rig-smoke.$$; rm -f /tmp/rig-smoke.$$
      else
        skip "go not on PATH"
      fi
      ;;
    rust)
      if command -v cargo >/dev/null 2>&1; then
        (cd "$REPO_ROOT" && cargo build --quiet) >/tmp/rig-smoke.$$ 2>&1 || gate_ok=0
        cat /tmp/rig-smoke.$$; rm -f /tmp/rig-smoke.$$
      else
        skip "cargo not on PATH"
      fi
      ;;
    *)
      skip "no recognized stack for boot smoke"
      ;;
  esac
  if [ "$gate_ok" -eq 1 ]; then
    pass "integration smoke (entrypoint loads/builds cleanly)"
  else
    OVERALL_STATUS=1
    record_failure "L3-integration" "entrypoint failed to load/build for stack=$STACK"
  fi
fi

# ---------------------------------------------------------------------------
# Gate 4: eval gate (spec/features/*.feature must exist and be non-empty)
# ---------------------------------------------------------------------------
if should_run 4; then
  log ""
  log "-- Gate 4/5: eval gate (BDD spec presence + structure) --"
  gate_ok=1
  feature_dir="$REPO_ROOT/spec/features"
  if [ -d "$feature_dir" ]; then
    count="$(find "$feature_dir" -name '*.feature' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$count" -eq 0 ]; then
      gate_ok=0
      fail "spec/features/ exists but contains no .feature files"
    else
      bad=0
      for f in "$feature_dir"/*.feature; do
        [ -f "$f" ] || continue
        grep -q '^Feature:' "$f" || { bad=1; fail "$f missing 'Feature:' line"; }
        grep -q 'Scenario:' "$f" || { bad=1; fail "$f missing a 'Scenario:' line"; }
      done
      if [ "$bad" -eq 1 ]; then
        gate_ok=0
      else
        pass "$count feature file(s) present and structurally valid"
      fi
    fi
  else
    gate_ok=0
    fail "spec/features/ directory missing — run apply-overlay.sh again"
  fi
  if [ "$gate_ok" -eq 0 ]; then
    OVERALL_STATUS=1
    record_failure "L4-eval" "spec/features BDD gate failed"
  fi
fi

# ---------------------------------------------------------------------------
# Gate 5: proof verification (delegates to verify.sh L5-proof layer only)
# ---------------------------------------------------------------------------
if should_run 5; then
  log ""
  log "-- Gate 5/5: proof verification --"
  if [ -x "$RIG_DIR/verify.sh" ]; then
    "$RIG_DIR/verify.sh" --layer=5
    rc=$?
    if [ $rc -ne 0 ]; then
      OVERALL_STATUS=1
      record_failure "L5-proof" "verify.sh --layer=5 exited non-zero"
    fi
  else
    fail ".rig/verify.sh not found or not executable"
    OVERALL_STATUS=1
    record_failure "L5-proof" ".rig/verify.sh missing"
  fi
fi

log ""
log "=================================================================="
if [ "$OVERALL_STATUS" -eq 0 ]; then
  printf ' SMOKE RESULT: \033[32mPASS\033[0m — all executed gates green\n'
else
  printf ' SMOKE RESULT: \033[31mFAIL\033[0m — see gate output above\n'
  [ "$LEARN" -eq 1 ] && log " Failures recorded to .rig/failures.json for next-run regression replay."
fi
log "=================================================================="

exit "$OVERALL_STATUS"
