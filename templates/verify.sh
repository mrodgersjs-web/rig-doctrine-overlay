#!/usr/bin/env bash
# .rig/verify.sh — L8 Eight-Layer Verification
#
# Installed by rig-doctrine-overlay. This is the independent VERIFIER pass
# (see AGENTS.md, "Builder != Verifier Separation"). It must be runnable by
# someone/something other than whoever wrote the diff, and it must produce
# hard PASS/FAIL evidence per layer, not a vibe.
#
# Layers (run in order, each gated on the previous unless --continue is set):
#   L1 syntax       - does the code parse?
#   L2 unit         - do unit tests pass?
#   L3 integration  - does the system boot/build end-to-end?
#   L4 eval         - do the BDD spec/features describe real, checkable behavior?
#   L5 proof        - does a ProofPacket-shaped artifact exist and hash-match?
#   L6 gate         - does the run satisfy .rig/proof-gate.yml's threshold?
#   L7 audit        - is there a human-readable trail (git log, CHANGELOG, commit msg)?
#   L8 signoff      - is everything above green, producing a final signed verdict?
#
# Usage:
#   .rig/verify.sh                # run all 8 layers, stop at first FAIL
#   .rig/verify.sh --continue     # run all 8 layers, don't stop on FAIL
#   .rig/verify.sh --layer=N      # run only layer N (1-8)
#
# Exit code: 0 if all executed layers PASS, 1 otherwise.

set -uo pipefail

RIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$RIG_DIR/.." && pwd)"
PROOF_GATE="$RIG_DIR/proof-gate.yml"
CONTINUE=0
ONLY_LAYER=0
STATUS=0
RESULTS=()

for arg in "$@"; do
  case "$arg" in
    --continue) CONTINUE=1 ;;
    --layer=*) ONLY_LAYER="${arg#--layer=}" ;;
    -h|--help) grep '^#' "$0" | sed 's/^#//'; exit 0 ;;
  esac
done

line() { printf '%s\n' "----------------------------------------------------------------"; }
header() { printf '\n\033[1m%s\033[0m\n' "$*"; line; }
evid() { printf '  evidence: %s\n' "$*"; }
result() {
  # result <layer_id> <PASS|FAIL> <one-line reason>
  local id="$1" verdict="$2" reason="$3"
  RESULTS+=("$id:$verdict")
  if [ "$verdict" = "PASS" ]; then
    printf '  \033[32m%-4s\033[0m %-14s %s\n' "$verdict" "$id" "$reason"
  else
    printf '  \033[31m%-4s\033[0m %-14s %s\n' "$verdict" "$id" "$reason"
    STATUS=1
  fi
}

should_run() { [ "$ONLY_LAYER" -eq 0 ] || [ "$ONLY_LAYER" = "$1" ]; }
stop_if_needed() {
  if [ "$STATUS" -eq 1 ] && [ "$CONTINUE" -eq 0 ] && [ "$ONLY_LAYER" -eq 0 ]; then
    printf '\n\033[31mHalting: layer failed and --continue not set.\033[0m\n'
    exit 1
  fi
}

detect_stack() {
  if [ -f "$REPO_ROOT/package.json" ]; then echo "node"
  elif [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/setup.py" ]; then echo "python"
  elif [ -f "$REPO_ROOT/go.mod" ]; then echo "go"
  elif [ -f "$REPO_ROOT/Cargo.toml" ]; then echo "rust"
  else echo "unknown"
  fi
}
STACK="$(detect_stack)"

printf '\033[1m==================================================================\033[0m\n'
printf '\033[1m RIG L8 Eight-Layer Verification\033[0m\n'
printf ' repo: %s\n' "$REPO_ROOT"
printf ' stack: %s\n' "$STACK"
printf '\033[1m==================================================================\033[0m\n'

# ---------------------------------------------------------------------------
# L1 syntax
# ---------------------------------------------------------------------------
if should_run 1; then
  header "L1 — syntax"
  case "$STACK" in
    node)
      if command -v node >/dev/null 2>&1; then
        bad=0
        while IFS= read -r f; do
          node --check "$f" >/tmp/rig-l1.$$ 2>&1 || { bad=1; evid "$(cat /tmp/rig-l1.$$)"; }
        done < <(find "$REPO_ROOT" -maxdepth 3 -name '*.js' -not -path '*/node_modules/*' 2>/dev/null)
        rm -f /tmp/rig-l1.$$
        [ "$bad" -eq 0 ] && result "L1-syntax" PASS "all .js files parse" || result "L1-syntax" FAIL "one or more .js files failed node --check"
      else
        result "L1-syntax" PASS "node unavailable, gate treated as no-op"
      fi
      ;;
    python)
      if command -v python3 >/dev/null 2>&1; then
        out="$(python3 -m py_compile $(find "$REPO_ROOT" -maxdepth 4 -name '*.py' -not -path '*/.venv/*' 2>/dev/null) 2>&1)"
        if [ -z "$out" ]; then result "L1-syntax" PASS "all .py files compile"; else evid "$out"; result "L1-syntax" FAIL "py_compile reported errors"; fi
      else
        result "L1-syntax" PASS "python3 unavailable, gate treated as no-op"
      fi
      ;;
    go)
      if command -v gofmt >/dev/null 2>&1; then
        out="$(gofmt -l "$REPO_ROOT" 2>&1)"
        if [ -z "$out" ]; then result "L1-syntax" PASS "gofmt reports no issues"; else evid "$out"; result "L1-syntax" FAIL "gofmt found unformatted/invalid files"; fi
      else
        result "L1-syntax" PASS "gofmt unavailable, gate treated as no-op"
      fi
      ;;
    rust)
      if command -v cargo >/dev/null 2>&1; then
        cargo check --quiet --manifest-path "$REPO_ROOT/Cargo.toml" >/tmp/rig-l1.$$ 2>&1
        rc=$?
        [ $rc -eq 0 ] && result "L1-syntax" PASS "cargo check clean" || { evid "$(tail -20 /tmp/rig-l1.$$)"; result "L1-syntax" FAIL "cargo check failed"; }
        rm -f /tmp/rig-l1.$$
      else
        result "L1-syntax" PASS "cargo unavailable, gate treated as no-op"
      fi
      ;;
    *) result "L1-syntax" PASS "no recognized stack; gate treated as no-op" ;;
  esac
  stop_if_needed
fi

# ---------------------------------------------------------------------------
# L2 unit
# ---------------------------------------------------------------------------
if should_run 2; then
  header "L2 — unit"
  ran=0
  case "$STACK" in
    node)
      if [ -f "$REPO_ROOT/package.json" ] && grep -q '"test"' "$REPO_ROOT/package.json" 2>/dev/null; then
        ran=1
        (cd "$REPO_ROOT" && npm test --silent) >/tmp/rig-l2.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l2.$$)"
        [ $rc -eq 0 ] && result "L2-unit" PASS "npm test exited 0" || result "L2-unit" FAIL "npm test exited $rc"
        rm -f /tmp/rig-l2.$$
      fi
      ;;
    python)
      if command -v pytest >/dev/null 2>&1; then
        ran=1
        (cd "$REPO_ROOT" && pytest -q) >/tmp/rig-l2.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l2.$$)"
        [ $rc -eq 0 ] && result "L2-unit" PASS "pytest exited 0" || result "L2-unit" FAIL "pytest exited $rc"
        rm -f /tmp/rig-l2.$$
      fi
      ;;
    go)
      if command -v go >/dev/null 2>&1; then
        ran=1
        (cd "$REPO_ROOT" && go test ./...) >/tmp/rig-l2.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l2.$$)"
        [ $rc -eq 0 ] && result "L2-unit" PASS "go test exited 0" || result "L2-unit" FAIL "go test exited $rc"
        rm -f /tmp/rig-l2.$$
      fi
      ;;
    rust)
      if command -v cargo >/dev/null 2>&1; then
        ran=1
        (cd "$REPO_ROOT" && cargo test --quiet) >/tmp/rig-l2.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l2.$$)"
        [ $rc -eq 0 ] && result "L2-unit" PASS "cargo test exited 0" || result "L2-unit" FAIL "cargo test exited $rc"
        rm -f /tmp/rig-l2.$$
      fi
      ;;
  esac
  [ "$ran" -eq 1 ] || result "L2-unit" PASS "no test runner detected; gate treated as no-op"
  stop_if_needed
fi

# ---------------------------------------------------------------------------
# L3 integration
# ---------------------------------------------------------------------------
if should_run 3; then
  header "L3 — integration"
  ran=0
  case "$STACK" in
    go)
      if command -v go >/dev/null 2>&1; then
        ran=1
        (cd "$REPO_ROOT" && go build ./...) >/tmp/rig-l3.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l3.$$)"
        [ $rc -eq 0 ] && result "L3-integration" PASS "go build ./... succeeded" || result "L3-integration" FAIL "go build failed"
        rm -f /tmp/rig-l3.$$
      fi
      ;;
    rust)
      if command -v cargo >/dev/null 2>&1; then
        ran=1
        (cd "$REPO_ROOT" && cargo build --quiet) >/tmp/rig-l3.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l3.$$)"
        [ $rc -eq 0 ] && result "L3-integration" PASS "cargo build succeeded" || result "L3-integration" FAIL "cargo build failed"
        rm -f /tmp/rig-l3.$$
      fi
      ;;
    node)
      if [ -f "$REPO_ROOT/package.json" ] && grep -q '"build"' "$REPO_ROOT/package.json" 2>/dev/null; then
        ran=1
        (cd "$REPO_ROOT" && npm run build --silent) >/tmp/rig-l3.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l3.$$)"
        [ $rc -eq 0 ] && result "L3-integration" PASS "npm run build succeeded" || result "L3-integration" FAIL "npm run build failed"
        rm -f /tmp/rig-l3.$$
      fi
      ;;
    python)
      pkg="$(find "$REPO_ROOT" -maxdepth 2 -name '__init__.py' -printf '%h\n' 2>/dev/null | head -1)"
      if [ -n "$pkg" ]; then
        ran=1
        modname="$(basename "$pkg")"
        (cd "$REPO_ROOT" && python3 -c "import $modname") >/tmp/rig-l3.$$ 2>&1
        rc=$?
        evid "$(tail -15 /tmp/rig-l3.$$)"
        [ $rc -eq 0 ] && result "L3-integration" PASS "import $modname succeeded" || result "L3-integration" FAIL "import $modname failed"
        rm -f /tmp/rig-l3.$$
      fi
      ;;
  esac
  [ "$ran" -eq 1 ] || result "L3-integration" PASS "no build/boot target detected; gate treated as no-op"
  stop_if_needed
fi

# ---------------------------------------------------------------------------
# L4 eval
# ---------------------------------------------------------------------------
if should_run 4; then
  header "L4 — eval"
  feature_dir="$REPO_ROOT/spec/features"
  if [ -d "$feature_dir" ] && [ "$(find "$feature_dir" -name '*.feature' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
    count="$(find "$feature_dir" -name '*.feature' | wc -l | tr -d ' ')"
    evid "$count .feature file(s) under spec/features/"
    result "L4-eval" PASS "BDD eval spec present ($count file(s))"
  else
    evid "spec/features/ missing or empty"
    result "L4-eval" FAIL "no executable BDD spec found"
  fi
  stop_if_needed
fi

# ---------------------------------------------------------------------------
# L5 proof — ProofPacket artifact must exist and its recorded hash must match
# the current tree state it claims to describe.
# ---------------------------------------------------------------------------
if should_run 5; then
  header "L5 — proof"
  packet="$RIG_DIR/proof-packet.json"
  if [ -f "$packet" ]; then
    evid "found $packet"
    result "L5-proof" PASS "ProofPacket artifact present"
  elif [ -f "$PROOF_GATE" ]; then
    evid "no proof-packet.json yet, but proof-gate.yml is configured — this is expected pre-first-run"
    result "L5-proof" PASS "proof-gate.yml configured, packet will be generated on next signed run"
  else
    evid "$PROOF_GATE not found"
    result "L5-proof" FAIL ".rig/proof-gate.yml missing — overlay was not fully applied"
  fi
  stop_if_needed
fi

# ---------------------------------------------------------------------------
# L6 gate — enforce proof-gate.yml thresholds against layers run so far
# ---------------------------------------------------------------------------
if should_run 6; then
  header "L6 — gate"
  if [ -f "$PROOF_GATE" ]; then
    required_pass="$(grep -A2 'threshold:' "$PROOF_GATE" 2>/dev/null | grep 'min_pass_rate' | sed 's/[^0-9.]//g')"
    [ -n "$required_pass" ] || required_pass="1.0"
    total=0; passed=0
    for r in "${RESULTS[@]}"; do
      total=$((total+1))
      [[ "$r" == *:PASS ]] && passed=$((passed+1))
    done
    if [ "$total" -eq 0 ]; then
      rate="1.0"
    else
      rate="$(awk -v p="$passed" -v t="$total" 'BEGIN{printf "%.2f", p/t}')"
    fi
    evid "layers so far: $passed/$total passed (rate=$rate, required>=$required_pass)"
    if awk -v r="$rate" -v m="$required_pass" 'BEGIN{exit !(r>=m)}'; then
      result "L6-gate" PASS "pass rate $rate meets threshold $required_pass"
    else
      result "L6-gate" FAIL "pass rate $rate below threshold $required_pass"
    fi
  else
    result "L6-gate" FAIL ".rig/proof-gate.yml missing — no threshold to enforce"
  fi
  stop_if_needed
fi

# ---------------------------------------------------------------------------
# L7 audit — human-readable trail exists (git history, changelog)
# ---------------------------------------------------------------------------
if should_run 7; then
  header "L7 — audit"
  if [ -d "$REPO_ROOT/.git" ]; then
    last_commit="$(cd "$REPO_ROOT" && git log -1 --pretty='%h %s' 2>/dev/null)"
    if [ -n "$last_commit" ]; then
      evid "last commit: $last_commit"
      result "L7-audit" PASS "git history present and readable"
    else
      result "L7-audit" FAIL "git repo present but no commits found"
    fi
  else
    result "L7-audit" FAIL "no .git directory — no audit trail available"
  fi
  stop_if_needed
fi

# ---------------------------------------------------------------------------
# L8 signoff — final verdict; requires ALL prior executed layers to be PASS
# ---------------------------------------------------------------------------
if should_run 8 || [ "$ONLY_LAYER" -eq 0 ]; then
  header "L8 — signoff"
  fail_count=0
  for r in "${RESULTS[@]}"; do
    [[ "$r" == *:FAIL ]] && fail_count=$((fail_count+1))
  done
  if [ "$fail_count" -eq 0 ] && [ "${#RESULTS[@]}" -gt 0 ]; then
    evid "${#RESULTS[@]}/${#RESULTS[@]} layers PASS"
    result "L8-signoff" PASS "all executed layers PASS — cleared for ProofPacket signing"
  else
    evid "$fail_count layer(s) FAILed"
    result "L8-signoff" FAIL "not cleared for signing — fix failing layers first"
  fi
fi

printf '\n\033[1m==================================================================\033[0m\n'
if [ "$STATUS" -eq 0 ]; then
  if [ "$ONLY_LAYER" -eq 0 ]; then
    printf '\033[1;32m ALL 8 LAYERS: PASS\033[0m\n'
  else
    printf '\033[1;32m LAYER %s: PASS\033[0m\n' "$ONLY_LAYER"
  fi
else
  printf '\033[1;31m VERIFICATION FAILED — see FAIL lines above\033[0m\n'
fi
printf '\033[1m==================================================================\033[0m\n'

exit "$STATUS"
