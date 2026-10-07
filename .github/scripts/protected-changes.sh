#!/usr/bin/env bash
# Prints the protected paths an agent changed on a PR branch, one per line.
#
# Usage: protected-changes.sh <base-ref> <old-commit> <new-commit>
#
# Protected: .github/, .claude/, .env* anywhere, plus the ERE in
# $PROTECTED_EXTRA (the project-setup action's `protected-pattern` output).
# A path counts only if it is in the PR's own diff against the base
# (three-dot) and its content differs between old and new, so merging the base
# branch in never trips it, and a protected file a human already put on the
# branch is fine until the agent touches it. Exits non-zero on any git error,
# so callers fail closed.
set -euo pipefail

base="$1" old="$2" new="$3"
pattern='^(\.github/|\.claude/)|(^|/)\.env'
[ -z "${PROTECTED_EXTRA:-}" ] || pattern="$pattern|$PROTECTED_EXTRA"

changed="$(git diff --no-renames --name-only "$base...$new")"
candidates="$(grep -E -- "$pattern" <<< "$changed" || true)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # --quiet exits 1 on a difference; anything else is an error.
  rc=0
  git diff --quiet "$old" "$new" -- "$f" || rc=$?
  case "$rc" in
    0) ;;
    1) echo "$f" ;;
    *) exit "$rc" ;;
  esac
done <<< "$candidates"
