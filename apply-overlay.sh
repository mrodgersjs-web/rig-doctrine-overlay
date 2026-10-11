#!/usr/bin/env bash
# apply-overlay.sh - RIG Doctrine Overlay installer
#
# Copies the overlay into a target repo: AGENTS.md doctrine, CLAUDE.md pointer,
# .rig/smoke.sh, .rig/verify.sh, .rig/rig_checks.py (doctrine checks),
# .rig/proof-gate.yml, an empty .rig/claims.jsonl ledger, a BDD example under
# spec/features/, and a governance header at the top of the README.
#
# Every file it creates or modifies is recorded in .rig/overlay/manifest.tsv,
# and the original of every modified file is saved under .rig/overlay/backup/,
# so uninstall-overlay.sh can put the target back exactly as it was.
#
# Usage:
#   ./apply-overlay.sh <target-repo-path>
#   ./apply-overlay.sh <target-repo-path> --force     # reinstall over a previous overlay install
#                                                    # (also overwrites an existing AGENTS.md/CLAUDE.md, backed up)
#   ./apply-overlay.sh <target-repo-path> --dry-run   # show what would happen, write nothing
#
# Exit codes: 0 success, 1 bad usage or incomplete install,
#             2 target already has .rig/ (overlay without --force, or a foreign .rig/)

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SELF_DIR/templates"

FORCE=0
DRY_RUN=0
TARGET=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "error: unknown option: $arg" >&2; exit 1 ;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$arg"; else echo "error: unexpected argument: $arg" >&2; exit 1; fi
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
MANIFEST_REL=".rig/overlay/manifest.tsv"
BACKUP_REL=".rig/overlay/backup"

log()  { printf '%s\n' "$*"; }
step() { printf '==> %s\n' "$*"; }
ok()   { printf '  OK    %s\n' "$*"; }
skip() { printf '  SKIP  %s\n' "$*"; }

# record <kind> <relpath>   kind: created | modified | dir
record() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  printf '%s\t%s\n' "$1" "$2" >> "$TARGET/$MANIFEST_REL"
}

# ensure_dir <relpath>: mkdir -p, recording each directory component it creates
ensure_dir() {
  local rel="$1" acc="" part
  local IFS='/'
  for part in $rel; do
    [ -n "$part" ] || continue
    acc="${acc:+$acc/}$part"
    if [ ! -d "$TARGET/$acc" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        log "  [dry-run] would create dir: $acc/"
      else
        mkdir "$TARGET/$acc"
        record dir "$acc"
      fi
    fi
  done
}

# backup_if_exists <relpath>: save the original before we modify it
backup_if_exists() {
  local rel="$1"
  [ "$DRY_RUN" -eq 1 ] && return 0
  if [ -f "$TARGET/$rel" ]; then
    mkdir -p "$(dirname "$TARGET/$BACKUP_REL/$rel")"
    cp -p "$TARGET/$rel" "$TARGET/$BACKUP_REL/$rel"
    record modified "$rel"
  else
    record created "$rel"
  fi
}

# install_file <src> <relpath-in-target>
install_file() {
  local src="$1" rel="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] would write: $rel"
    return 0
  fi
  ensure_dir "$(dirname "$rel")"
  # files under .rig/ are removed wholesale on uninstall; no per-file record needed
  case "$rel" in
    .rig/*) ;;
    *) backup_if_exists "$rel" ;;
  esac
  cp "$src" "$TARGET/$rel"
  ok "$rel"
}

log "=================================================================="
log " RIG Doctrine Overlay - applying to: $TARGET"
log " overlay source: $SELF_DIR"
log " mode: $([ "$DRY_RUN" -eq 1 ] && echo 'dry-run' || echo 'apply')$([ "$FORCE" -eq 1 ] && echo ' (force)' || echo '')"
log "=================================================================="

# ---------------------------------------------------------------------------
# Step 0: existing .rig/
# ---------------------------------------------------------------------------
step "Step 0/7: checking for existing .rig/ directory"
if [ -d "$TARGET/.rig" ]; then
  if [ ! -f "$TARGET/$MANIFEST_REL" ]; then
    echo "error: $TARGET/.rig exists but was not installed by this overlay (no $MANIFEST_REL)." >&2
    echo "Refusing to touch it, even with --force: uninstall could not restore it." >&2
    exit 2
  fi
  if [ "$FORCE" -ne 1 ]; then
    echo "error: $TARGET already has the overlay installed. Re-run with --force to reinstall." >&2
    exit 2
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] would uninstall the previous overlay, then reinstall"
  else
    step "removing previous overlay install first (--force)"
    "$SELF_DIR/uninstall-overlay.sh" "$TARGET" >/dev/null || { echo "error: uninstall of previous overlay failed" >&2; exit 1; }
    ok "previous overlay removed; target restored"
  fi
else
  ok "no existing .rig/ - clean install"
fi
if [ "$DRY_RUN" -ne 1 ]; then
  mkdir -p "$TARGET/.rig/overlay/backup"
  : > "$TARGET/$MANIFEST_REL"
  record dir ".rig"
fi

# ---------------------------------------------------------------------------
# Step 1: AGENTS.md + CLAUDE.md
# ---------------------------------------------------------------------------
step "Step 1/7: installing AGENTS.md (TAC doctrine)"
if [ -f "$TARGET/AGENTS.md" ] && [ "$FORCE" -ne 1 ]; then
  skip "AGENTS.md already exists - preserving (use --force to overwrite)"
else
  install_file "$TEMPLATES_DIR/AGENTS.md" "AGENTS.md"
fi
if [ -f "$TARGET/CLAUDE.md" ] && [ "$FORCE" -ne 1 ]; then
  skip "CLAUDE.md already exists - preserving"
else
  install_file "$TEMPLATES_DIR/CLAUDE.md" "CLAUDE.md"
fi

# ---------------------------------------------------------------------------
# Step 2-3: harness scripts
# ---------------------------------------------------------------------------
step "Step 2/7: installing .rig/smoke.sh (L10 smoke harness)"
install_file "$TEMPLATES_DIR/smoke.sh" ".rig/smoke.sh"
step "Step 3/7: installing .rig/verify.sh and .rig/rig_checks.py (L8 verification + doctrine checks)"
install_file "$TEMPLATES_DIR/verify.sh" ".rig/verify.sh"
install_file "$TEMPLATES_DIR/rig_checks.py" ".rig/rig_checks.py"
if [ "$DRY_RUN" -ne 1 ]; then
  chmod +x "$TARGET/.rig/smoke.sh" "$TARGET/.rig/verify.sh" "$TARGET/.rig/rig_checks.py"
  [ -f "$TARGET/.rig/failures.json" ] || echo '{"failures": []}' > "$TARGET/.rig/failures.json"
  [ -f "$TARGET/.rig/claims.jsonl" ] || printf '%s\n' '# one JSON object per line: {"id": "...", "status": "done", "claim": "...", "evidence": {"path": "..."} or {"command": "...", "output": "..."}}' > "$TARGET/.rig/claims.jsonl"
  ok ".rig/failures.json + .rig/claims.jsonl ledgers"
fi

# ---------------------------------------------------------------------------
# Step 4: spec/features/ (BDD)
# ---------------------------------------------------------------------------
step "Step 4/7: installing spec/features/ (BDD)"
if [ -d "$TARGET/spec/features" ] && [ -n "$(find "$TARGET/spec/features" -name '*.feature' 2>/dev/null | head -1)" ]; then
  skip "spec/features/ already contains .feature files - preserving"
else
  install_file "$TEMPLATES_DIR/feature.template.feature" "spec/features/example.feature"
fi

# ---------------------------------------------------------------------------
# Step 5: .rig/proof-gate.yml
# ---------------------------------------------------------------------------
step "Step 5/7: installing .rig/proof-gate.yml"
repo_slug="$(basename "$TARGET" | tr -cd 'A-Za-z0-9._-')"
if [ "$DRY_RUN" -eq 1 ]; then
  log "  [dry-run] would write: .rig/proof-gate.yml (slug=$repo_slug)"
else
  sed "s/<REPLACE: repo-slug>/$repo_slug/g; s#<repo-slug>#$repo_slug#g" \
    "$TEMPLATES_DIR/proof-gate.yml" > "$TARGET/.rig/proof-gate.yml"
  ok ".rig/proof-gate.yml (metadata.name=$repo_slug)"
fi

# ---------------------------------------------------------------------------
# Step 6: README header
# ---------------------------------------------------------------------------
step "Step 6/7: prepending governance header to README"
readme_rel=""
for candidate in README.md Readme.md readme.md README.rst README; do
  if [ -f "$TARGET/$candidate" ]; then readme_rel="$candidate"; break; fi
done
if [ -z "$readme_rel" ]; then
  install_file "$TEMPLATES_DIR/README-header.md" "README.md"
elif grep -q 'FDE STANDARD HEADER' "$TARGET/$readme_rel" 2>/dev/null; then
  skip "$readme_rel already has the header - preserving"
elif [ "$DRY_RUN" -eq 1 ]; then
  log "  [dry-run] would prepend header to $readme_rel"
else
  backup_if_exists "$readme_rel"
  tmp="$(mktemp)"
  cat "$TEMPLATES_DIR/README-header.md" "$TARGET/$readme_rel" > "$tmp"
  cat "$tmp" > "$TARGET/$readme_rel"   # keep the original file's mode
  rm -f "$tmp"
  ok "$readme_rel -> header prepended"
fi

# ---------------------------------------------------------------------------
# Step 7: sanity check
# ---------------------------------------------------------------------------
step "Step 7/7: sanity-checking the install"
if [ "$DRY_RUN" -eq 1 ]; then
  log "  [dry-run] skipping sanity check"
else
  missing=0
  for f in AGENTS.md .rig/smoke.sh .rig/verify.sh .rig/rig_checks.py .rig/proof-gate.yml "$MANIFEST_REL"; do
    if [ -f "$TARGET/$f" ]; then ok "$f present"; else echo "  MISSING $f" >&2; missing=1; fi
  done
  if [ -n "$(find "$TARGET/spec/features" -name '*.feature' 2>/dev/null | head -1)" ]; then
    ok "spec/features/*.feature present"
  else
    echo "  MISSING spec/features/*.feature" >&2; missing=1
  fi
  if [ "$missing" -eq 1 ]; then
    echo "error: overlay install incomplete - see MISSING lines above" >&2
    exit 1
  fi
fi

log ""
log "=================================================================="
log " RIG Doctrine Overlay applied."
log " Next: cd $TARGET"
log "   python3 .rig/rig_checks.py all   # claims / tests / secrets"
log "   .rig/verify.sh --continue        # 8-layer verification"
log "   .rig/smoke.sh --learn            # smoke gates + failure ledger"
log " Remove with: $SELF_DIR/uninstall-overlay.sh $TARGET"
log "=================================================================="
