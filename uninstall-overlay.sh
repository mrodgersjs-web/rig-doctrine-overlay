#!/usr/bin/env bash
# uninstall-overlay.sh - remove the RIG Doctrine Overlay from a target repo
#
# Reads <target>/.rig/overlay/manifest.tsv written by apply-overlay.sh,
# restores every file the installer modified from .rig/overlay/backup/,
# deletes every file and directory the installer created, then removes .rig/.
# The target ends up byte-identical to its pre-install state, except for files
# you edited after install that the installer created (those are deleted) and
# anything you added under .rig/ (also deleted).
#
# Usage:
#   ./uninstall-overlay.sh <target-repo-path>
#   ./uninstall-overlay.sh <target-repo-path> --dry-run
#
# Exit codes: 0 removed, 1 bad usage, 2 no overlay manifest found

set -uo pipefail

DRY_RUN=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown option: $arg" >&2; exit 1 ;;
    *) if [ -z "$TARGET" ]; then TARGET="$arg"; else echo "error: unexpected argument: $arg" >&2; exit 1; fi ;;
  esac
done
[ -n "$TARGET" ] || { echo "error: missing <target-repo-path>" >&2; exit 1; }
[ -d "$TARGET" ] || { echo "error: not a directory: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
MANIFEST="$TARGET/.rig/overlay/manifest.tsv"
BACKUP="$TARGET/.rig/overlay/backup"

if [ ! -f "$MANIFEST" ]; then
  echo "error: no overlay manifest at $MANIFEST - nothing to uninstall" >&2
  exit 2
fi

act() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}

echo "==> removing RIG Doctrine Overlay from $TARGET"
dirs=()
while IFS=$'\t' read -r kind rel; do
  [ -n "${rel:-}" ] || continue
  case "$rel" in /*|*..*) echo "error: unsafe manifest path: $rel" >&2; exit 1 ;; esac
  case "$kind" in
    modified)
      act cp -p "$BACKUP/$rel" "$TARGET/$rel"
      echo "  restored $rel"
      ;;
    created)
      act rm -f "$TARGET/$rel"
      echo "  removed  $rel"
      ;;
    dir) dirs+=("$rel") ;;
    *) echo "error: unknown manifest entry: $kind" >&2; exit 1 ;;
  esac
done < "$MANIFEST"

# directories in reverse creation order (deepest first); .rig is removed wholesale
for (( i=${#dirs[@]}-1; i>=0; i-- )); do
  d="${dirs[$i]}"
  if [ "$d" = ".rig" ]; then
    act rm -rf "${TARGET:?}/.rig"
    echo "  removed  .rig/"
  elif [ -d "$TARGET/$d" ]; then
    if [ -z "$(ls -A "$TARGET/$d")" ]; then
      act rmdir "$TARGET/$d"
      echo "  removed  $d/"
    else
      echo "  kept     $d/ (contains files added after install)"
    fi
  fi
done
echo "==> done"
