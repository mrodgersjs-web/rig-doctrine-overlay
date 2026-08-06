#!/usr/bin/env bash
# apply-overlay.sh — RIG Doctrine Overlay installer
#
# Transforms any AI repo into a RIG-governed FDE-standard repo by copying in
# the 5-layer overlay: TAC doctrine, L10 self-evolving smoke tests, L8
# eight-layer verification, OpenSpec BDD, and ProofPacket gates.
#
# Usage:
#   ./apply-overlay.sh <target-repo-path>
#   ./apply-overlay.sh <target-repo-path> --force     # overwrite existing .rig/
#   ./apply-overlay.sh <target-repo-path> --dry-run    # show what would happen
#
# Exit codes: 0 success, 1 bad usage, 2 target already has .rig/ (without --force)

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SELF_DIR/templates"

FORCE=0
DRY_RUN=0
TARGET=""

usage() {
  grep '^#' "$0" | sed 's/^#//'
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$arg"; fi
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "error: missing <target-repo-path>" >&2
  usage
  exit 1
fi

if [ ! -d "$TARGET" ]; then
  echo "error: target repo path does not exist or is not a directory: $TARGET" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

log()  { printf '%s\n' "$*"; }
step() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$*"; }

do_copy() {
  # do_copy <src> <dst> <label>
  local src="$1" dst="$2" label="$3"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] would write: $dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  ok "$label -> ${dst#$TARGET/}"
}

log "=================================================================="
log " RIG Doctrine Overlay — applying to: $TARGET"
log " overlay source: $SELF_DIR"
log " mode: $([ "$DRY_RUN" -eq 1 ] && echo 'dry-run' || echo 'apply')$([ "$FORCE" -eq 1 ] && echo ' (force)' || echo '')"
log "=================================================================="

# ---------------------------------------------------------------------------
# Step 0: check for existing .rig/
# ---------------------------------------------------------------------------
step "Step 0/7: checking for existing .rig/ directory"
if [ -d "$TARGET/.rig" ] && [ "$FORCE" -ne 1 ]; then
  echo ""
  echo "error: $TARGET/.rig already exists." >&2
  echo "This repo may already have the RIG overlay applied. Re-run with --force" >&2
  echo "to overwrite, or inspect $TARGET/.rig manually first." >&2
  exit 2
elif [ -d "$TARGET/.rig" ]; then
  skip "existing .rig/ found — will overwrite (--force set)"
else
  ok "no existing .rig/ — clean install"
fi
[ "$DRY_RUN" -eq 1 ] || mkdir -p "$TARGET/.rig"

# ---------------------------------------------------------------------------
# Step 1: AGENTS.md from template
# ---------------------------------------------------------------------------
step "Step 1/7: installing AGENTS.md (TAC doctrine)"
if [ -f "$TARGET/AGENTS.md" ] && [ "$FORCE" -ne 1 ]; then
  skip "AGENTS.md already exists at target — preserving (use --force to overwrite)"
else
  do_copy "$TEMPLATES_DIR/AGENTS.md" "$TARGET/AGENTS.md" "AGENTS.md"
fi

# CLAUDE.md / codex context files commonly point at AGENTS.md by convention;
# create a thin pointer for tools that specifically look for CLAUDE.md.
if [ ! -f "$TARGET/CLAUDE.md" ] || [ "$FORCE" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] would write: $TARGET/CLAUDE.md"
  else
    cat > "$TARGET/CLAUDE.md" <<'EOF'
# CLAUDE.md

This repository's agent doctrine lives in [`AGENTS.md`](./AGENTS.md) — read it
first. `AGENTS.md` is the canonical, tool-agnostic context root (Claude Code,
Codex, Cursor, Aider, and others all read it); this file exists only because
some Claude-specific tooling looks for `CLAUDE.md` by name.
EOF
    ok "CLAUDE.md -> pointer to AGENTS.md"
  fi
else
  skip "CLAUDE.md already exists — preserving"
fi

# ---------------------------------------------------------------------------
# Step 2: .rig/smoke.sh (L10)
# ---------------------------------------------------------------------------
step "Step 2/7: installing .rig/smoke.sh (L10 self-evolving smoke harness)"
do_copy "$TEMPLATES_DIR/smoke.sh" "$TARGET/.rig/smoke.sh" "smoke.sh"
[ "$DRY_RUN" -eq 1 ] || chmod +x "$TARGET/.rig/smoke.sh"

# ---------------------------------------------------------------------------
# Step 3: .rig/verify.sh (L8)
# ---------------------------------------------------------------------------
step "Step 3/7: installing .rig/verify.sh (L8 eight-layer verification)"
do_copy "$TEMPLATES_DIR/verify.sh" "$TARGET/.rig/verify.sh" "verify.sh"
[ "$DRY_RUN" -eq 1 ] || chmod +x "$TARGET/.rig/verify.sh"

# ---------------------------------------------------------------------------
# Step 4: spec/features/ (BDD)
# ---------------------------------------------------------------------------
step "Step 4/7: installing spec/features/ (OpenSpec BDD)"
if [ -d "$TARGET/spec/features" ] && [ "$(find "$TARGET/spec/features" -name '*.feature' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  skip "spec/features/ already contains .feature files — preserving"
else
  do_copy "$TEMPLATES_DIR/feature.template.feature" "$TARGET/spec/features/example.feature" "spec/features/example.feature"
fi

# ---------------------------------------------------------------------------
# Step 5: .rig/proof-gate.yml
# ---------------------------------------------------------------------------
step "Step 5/7: installing .rig/proof-gate.yml (ProofPacket config)"
repo_slug="$(basename "$TARGET")"
if [ "$DRY_RUN" -eq 1 ]; then
  log "  [dry-run] would write: $TARGET/.rig/proof-gate.yml (slug=$repo_slug)"
else
  sed "s/<REPLACE: repo-slug>/$repo_slug/g; s#<repo-slug>#$repo_slug#g" \
    "$TEMPLATES_DIR/proof-gate.yml" > "$TARGET/.rig/proof-gate.yml"
  ok "proof-gate.yml -> .rig/proof-gate.yml (metadata.name=$repo_slug)"
fi

# seed an empty failures ledger so smoke.sh --learn has somewhere to write
if [ ! -f "$TARGET/.rig/failures.json" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] would write: $TARGET/.rig/failures.json"
  else
    echo '{"failures": []}' > "$TARGET/.rig/failures.json"
    ok "failures.json -> .rig/failures.json (empty ledger)"
  fi
fi

# ---------------------------------------------------------------------------
# Step 6: update README with FDE standard header
# ---------------------------------------------------------------------------
step "Step 6/7: prepending FDE standard header to README"
readme=""
for candidate in README.md Readme.md README.rst README; do
  if [ -f "$TARGET/$candidate" ]; then readme="$TARGET/$candidate"; break; fi
done

if [ -z "$readme" ]; then
  readme="$TARGET/README.md"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] no README found; would create $readme from header template"
  else
    cp "$TEMPLATES_DIR/README-header.md" "$readme"
    ok "no README found -> created README.md from header template"
  fi
else
  if grep -q "RIG Doctrine Overlay" "$readme" 2>/dev/null && [ "$FORCE" -ne 1 ]; then
    skip "$( basename "$readme") already has the FDE header — preserving"
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      log "  [dry-run] would prepend FDE header to $readme (stripping any prior header first)"
    else
      # Idempotent under repeated --force: if a prior FDE header block is
      # already present, strip it out (start marker through its trailing
      # separator line, plus a leading bare separator line if present)
      # before prepending a fresh copy — this prevents header duplication
      # on repeated --force applies.
      body="$readme"
      start_line="$(grep -n 'FDE STANDARD HEADER — installed by rig-doctrine-overlay' "$readme" 2>/dev/null | head -1 | cut -d: -f1)"
      if [ -n "$start_line" ]; then
        prev_line=$((start_line - 1))
        if [ "$prev_line" -ge 1 ] && sed -n "${prev_line}p" "$readme" | grep -qE '^<!-- =+ -->$'; then
          start_line="$prev_line"
        fi
        end_marker_line="$(grep -n 'END FDE STANDARD HEADER' "$readme" 2>/dev/null | head -1 | cut -d: -f1)"
        if [ -n "$end_marker_line" ]; then
          end_line=$((end_marker_line + 1))
          stripped="$(mktemp)"
          sed "${start_line},${end_line}d" "$readme" > "$stripped"
          # drop one leading blank line left behind, if any
          sed -i.bak '1{/^$/d}' "$stripped" 2>/dev/null; rm -f "${stripped}.bak"
          body="$stripped"
        fi
      fi
      tmp="$(mktemp)"
      cat "$TEMPLATES_DIR/README-header.md" "$body" > "$tmp"
      mv "$tmp" "$readme"
      [ -n "${stripped:-}" ] && [ -f "$stripped" ] && rm -f "$stripped"
      ok "$(basename "$readme") -> FDE header prepended (idempotent)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Step 7: sanity check the install
# ---------------------------------------------------------------------------
step "Step 7/7: sanity-checking the install"
if [ "$DRY_RUN" -eq 1 ]; then
  log "  [dry-run] skipping sanity check"
else
  missing=0
  for f in AGENTS.md .rig/smoke.sh .rig/verify.sh .rig/proof-gate.yml; do
    if [ -f "$TARGET/$f" ]; then
      ok "$f present"
    else
      echo "  MISSING $f" >&2
      missing=1
    fi
  done
  if [ "$(find "$TARGET/spec/features" -name '*.feature' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
    ok "spec/features/*.feature present"
  else
    echo "  MISSING spec/features/*.feature" >&2
    missing=1
  fi
  if [ "$missing" -eq 1 ]; then
    echo "" >&2
    echo "error: overlay install incomplete — see MISSING lines above" >&2
    exit 1
  fi
fi

log ""
log "=================================================================="
log " RIG Doctrine Overlay applied successfully."
log ""
log " Next steps:"
log "   1. cd $TARGET"
log "   2. Edit AGENTS.md 'Project Conventions' section for this repo's stack"
log "   3. Replace spec/features/example.feature with real BDD scenarios"
log "   4. Run: .rig/smoke.sh --learn"
log "   5. Run: .rig/verify.sh"
log "   6. export RIG_PROOF_KEY=... and wire signing into CI (.rig/proof-gate.yml)"
log "=================================================================="
