#!/bin/bash
# Installs dependencies when Claude Code starts in a cloud or CI session, so the
# agent's first typecheck/test run works without it having to figure out setup.
# Local sessions skip it: your machine already has node_modules.
#
# CLAUDE_CODE_REMOTE is set by Claude Code cloud sessions. GitHub Actions sets
# CI=true. Either one means "fresh container, nothing installed".
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && [ "${CI:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# `install` in .claude/agent-ci.json, the same command CI runs. Without a
# config (or jq), guess from what the repo contains.
install_cmd=""
if [ -f .claude/agent-ci.json ] && command -v jq > /dev/null; then
  install_cmd="$(jq -r '.install // ""' .claude/agent-ci.json)"
fi

if [ -n "$install_cmd" ]; then
  install=(bash -c "$install_cmd")
elif [ -f go.mod ]; then
  install=(go mod download)
elif [ -f pnpm-lock.yaml ]; then
  install=(pnpm install --frozen-lockfile)
elif [ -f yarn.lock ]; then
  install=(yarn install --frozen-lockfile)
elif [ -f bun.lockb ] || [ -f bun.lock ]; then
  install=(bun install --frozen-lockfile)
elif [ -f package-lock.json ]; then
  install=(npm ci)
else
  exit 0
fi

# Quiet on success, loud on failure: a noisy hook burns context tokens every session.
log="$(mktemp)"
if ! "${install[@]}" > "$log" 2>&1; then
  cat "$log" >&2
  rm -f "$log"
  exit 1
fi
rm -f "$log"
