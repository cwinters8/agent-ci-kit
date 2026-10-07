#!/usr/bin/env bash
# Prints the protected paths an agent changed on a PR branch, one per line
# (shell-quoted with printf %q when a name holds a control character).
#
# Usage: protected-changes.sh <base-ref> <old-commit> <new-commit>
#
# Protected: .github/, .claude/, .env* anywhere, plus the ERE in
# $PROTECTED_EXTRA (the project-setup action's `protected-pattern` output).
# A path counts only if it is in the PR's own diff against the base
# (three-dot) at old or at new, and its content differs between old and new.
# So merging the base branch in never trips it, a protected file a human
# already put on the branch is fine until the agent touches it, and reverting
# that file to the base version still counts as touching it. Exits non-zero
# on any git error, so callers fail closed.
set -euo pipefail

base="$1" old="$2" new="$3"
pattern='^(\.github/|\.claude/)|(^|/)\.env'
[ -z "${PROTECTED_EXTRA:-}" ] || pattern="$pattern|$PROTECTED_EXTRA"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Names travel NUL-delimited: `git diff --name-only` without -z C-quotes a
# name holding a newline or tab ("\".github/a\nb\""), which would slip past
# the anchored pattern.
at_old="$tmp/old" at_new="$tmp/new"
git diff -z --no-renames --name-only "$base...$old" > "$at_old"
git diff -z --no-renames --name-only "$base...$new" > "$at_new"
while IFS= read -r -d '' f; do
  [[ $f =~ $pattern ]] || continue
  # --quiet exits 1 on a difference; anything else is an error. The literal
  # pathspec keeps glob characters in a name from matching other files.
  rc=0
  git diff --quiet "$old" "$new" -- ":(literal)$f" || rc=$?
  case "$rc" in
    0) ;;
    1) if [[ $f == *[[:cntrl:]]* ]]; then printf '%q\n' "$f"; else printf '%s\n' "$f"; fi ;;
    *) exit "$rc" ;;
  esac
done < <(sort -zu "$at_old" "$at_new")
