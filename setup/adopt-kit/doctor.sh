#!/usr/bin/env bash
# Checks that the agent CI kit is fully set up in the current repo: files,
# config, path filters, and the GitHub side (secrets, labels, branch
# protection). Read-only: it changes nothing locally or on GitHub.
#
# Run from the root of the repo you adopted the kit into:
#   bash ~/.claude/skills/adopt-kit/doctor.sh [owner/repo]
#
# Exits 1 if anything would stop the agents from working, 0 otherwise.
# Warnings (!) are worth fixing but do not block a first run.
set -uo pipefail

fails=0
warns=0
if [ -t 1 ]; then g=$'\033[32m' y=$'\033[33m' r=$'\033[31m' n=$'\033[0m'; else g='' y='' r='' n=''; fi
ok()   { printf '  %s✓%s %s\n' "$g" "$n" "$1"; }
warn() { printf '  %s!%s %s\n' "$y" "$n" "$1"; warns=$((warns + 1)); }
fail() { printf '  %s✗%s %s\n' "$r" "$n" "$1"; fails=$((fails + 1)); }
skip() { printf '  - %s\n' "$1"; }
section() { printf '\n%s\n' "$1"; }

cfg=.claude/agent-ci.json
schema=.claude/agent-ci.schema.json
labels=(agent:fix agent:fix-opus agent:needs-human agent:large-diff)
skills=(action-versions code-review pr-preflight review-sweep security-review)

# ---------------------------------------------------------------- tools
section "Tools"
for t in git jq gh; do
  if command -v "$t" > /dev/null; then ok "$t installed"; else fail "$t not installed"; fi
done
command -v jq > /dev/null || { echo; echo "jq is required for the remaining checks."; exit 1; }

root="$(git rev-parse --show-toplevel 2> /dev/null)" || { fail "not inside a git repo"; exit 1; }
cd "$root" || exit 1

# ---------------------------------------------------------------- files
section "Kit files"
for f in AGENTS.md CLAUDE.md .claude/project-profile.md "$cfg" "$schema" \
  .claude/settings.json .claude/hooks/session-start.sh \
  .github/actions/project-setup/action.yml .github/ISSUE_TEMPLATE/agent-fix.yml; do
  if [ -f "$f" ]; then ok "$f"; else fail "$f missing"; fi
done
if [ ! -f .github/workflows/pr-checks.yml ]; then
  warn "no pr-checks.yml: fine only if your own CI runs commands.check on every PR, agent PRs included"
fi
for s in "${skills[@]}"; do
  [ -f ".claude/skills/$s/SKILL.md" ] || fail ".claude/skills/$s/SKILL.md missing"
done
agent_workflows=0
for w in claude-fix-issue claude claude-review-sweep; do
  [ -f ".github/workflows/$w.yml" ] && agent_workflows=$((agent_workflows + 1))
done
if [ "$agent_workflows" -gt 0 ]; then
  ok "$agent_workflows agent workflow(s) in .github/workflows/"
else
  fail "no agent workflows (claude-fix-issue.yml, claude.yml, claude-review-sweep.yml)"
fi
if [ -f CLAUDE.md ] && ! grep -q '@AGENTS.md' CLAUDE.md; then
  warn "CLAUDE.md does not import @AGENTS.md; Claude Code may not read the agent rules"
fi
if [ -f .claude/settings.json ] && ! grep -q 'session-start.sh' .claude/settings.json; then
  warn ".claude/settings.json does not run hooks/session-start.sh; cloud sessions will start without dependencies"
fi

# ---------------------------------------------------------------- config
section "Project config ($cfg)"
if [ ! -f "$cfg" ]; then
  skip "skipped: no config"
elif ! jq empty "$cfg" 2> /dev/null; then
  fail "$cfg is not valid JSON"
else
  # Command names and the allowed-character pattern come from the schema the
  # workflows were built against, so this check cannot drift from it.
  roles='["install","format","lint","typecheck","test","build","check"]'
  pattern='^[A-Za-z0-9 ._:/*=@+-]+$'
  if [ -f "$schema" ] && jq empty "$schema" 2> /dev/null; then
    roles="$(jq -c '.properties.commands.properties | keys' "$schema")"
    pattern="$(jq -r '."$defs".command.pattern' "$schema")"
  fi
  errors="$(jq -r --argjson roles "$roles" --arg pat "$pattern" '
    def list: if type == "array" then .[] else . end;
    [
      (if (.toolchain | type) != "object" then "toolchain: required (use {} if the runner already has your runtime)" else empty end),
      (.toolchain // {} | keys[] | select(IN("go", "node", "python") | not) | "toolchain.\(.): not supported; use go, node, python or {}"),
      (if (.commands | type) != "object" then "commands: required" else empty end),
      (.commands // {} | keys[] | select(. as $k | $roles | index($k) | not) | "commands.\(.): unknown name; use one of \($roles | join(", "))"),
      (if ([.commands.check // empty | list] | length) == 0 then "commands.check: required" else empty end),
      (([.commands // {} | to_entries[] | select(.key != "install") | .value | list] + (.allow // []))[]
        | select(type != "string" or (test($pat) | not))
        | "not a plain command (no quotes or shell operators; wrap it in a Makefile target or package script): \(tojson)")
    ] | .[]' "$cfg")"
  if [ -n "$errors" ]; then
    while IFS= read -r e; do fail "$e"; done <<< "$errors"
  else
    ok "fields and commands valid"
  fi

  while IFS= read -r vf; do
    [ -n "$vf" ] || continue
    if [ -f "$vf" ]; then ok "version file $vf exists"; else fail "toolchain version file $vf does not exist"; fi
  done < <(jq -r '.toolchain // {} | .[] | .version_file // empty' "$cfg")
  while IFS= read -r df; do
    [ -n "$df" ] || continue
    [ -e "$df" ] || warn "dependency file $df does not exist"
  done < <(jq -r '.dependency_files // [] | .[]' "$cfg")
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$p" ] || warn "protected path $p does not exist (typo?)"
  done < <(jq -r '.protected_paths // [] | .[]' "$cfg")
fi

# ---------------------------------------------------------------- sample leftovers
section "Sample leftovers"
leftover=0
if [ -f AGENTS.md ] && grep -qiE 'sample todo API|JSON todo API' AGENTS.md; then
  fail "AGENTS.md project sections still describe the kit's sample todo API"; leftover=1
fi
if [ -f .claude/project-profile.md ] && grep -qE 'internal/store|sample todo API' .claude/project-profile.md; then
  fail ".claude/project-profile.md still describes the kit's sample todo API"; leftover=1
fi
has_go=0
git ls-files '*.go' | grep -q . && has_go=1
if [ "$has_go" = 0 ]; then
  if [ -f "$cfg" ] && jq -e '.toolchain.go' "$cfg" > /dev/null 2>&1; then
    fail "$cfg sets up Go, but the repo has no Go files"; leftover=1
  fi
  for w in pr-checks build-image; do
    f=".github/workflows/$w.yml"
    if [ -f "$f" ] && grep -qE "^\s*- '\*\*\.go'" "$f"; then
      fail "$f paths: filter still lists the sample's Go files; point it at your source"; leftover=1
    fi
  done
fi
if [ -f .github/workflows/build-image.yml ]; then
  dockerfile="$(jq -r '.image.dockerfile // "Dockerfile"' "$cfg" 2> /dev/null || echo Dockerfile)"
  if [ ! -f "$dockerfile" ]; then
    fail "build-image.yml is present but $dockerfile is not; delete the workflow if you ship no image"; leftover=1
  elif [ -f "$cfg" ] && ! jq -e '.image' "$cfg" > /dev/null 2>&1; then
    fail "build-image.yml is present but $cfg has no image section"; leftover=1
  fi
fi
[ "$leftover" = 0 ] && ok "nothing left over from the sample project"

# ---------------------------------------------------------------- GitHub
section "GitHub"
repo="${1:-}"
if [ -z "$repo" ]; then
  url="$(git remote get-url origin 2> /dev/null || true)"
  repo="$(sed -E 's#^(git@[^:]+:|ssh://git@[^/]+/|https?://[^/]+/)##; s#\.git$##' <<< "$url")"
fi
if ! command -v gh > /dev/null; then
  skip "skipped: gh not installed"
elif ! [[ "$repo" =~ ^[^/]+/[^/]+$ ]] || ! info="$(gh api "repos/$repo" 2> /dev/null)"; then
  fail "cannot read repo '${repo:-?}' with gh; run gh auth login, or pass owner/repo as the first argument"
else
  default="$(jq -r .default_branch <<< "$info")"
  ok "$repo (default branch $default, $(jq -r .visibility <<< "$info"))"
  if [ "$(jq -r .visibility <<< "$info")" = public ]; then
    warn "repo is public: read docs/GUARDRAILS.md 'Before enabling on a public repo'"
  fi

  if enabled="$(gh api "repos/$repo/actions/permissions" --jq .enabled 2> /dev/null)"; then
    if [ "$enabled" = true ]; then ok "GitHub Actions enabled"; else fail "GitHub Actions is disabled for this repo"; fi
  else
    skip "could not read Actions settings (needs admin)"
  fi

  if secrets="$(gh api "repos/$repo/actions/secrets" --paginate --jq '.secrets[].name' 2> /dev/null)"; then
    if grep -qxE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' <<< "$secrets"; then
      ok "Claude credential secret set"
    else
      fail "no CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY secret"
    fi
    if grep -qx AGENT_PR_TOKEN <<< "$secrets"; then
      ok "AGENT_PR_TOKEN secret set"
    else
      fail "no AGENT_PR_TOKEN secret; CI will not run on agent PRs"
    fi
  else
    skip "could not list secrets (needs admin); check Settings > Secrets and variables > Actions"
  fi

  if have="$(gh api "repos/$repo/labels" --paginate --jq '.[].name' 2> /dev/null)"; then
    missing=()
    for l in "${labels[@]}"; do grep -qxF "$l" <<< "$have" || missing+=("$l"); done
    if [ "${#missing[@]}" = 0 ]; then ok "agent labels exist"; else fail "missing labels: ${missing[*]}"; fi
  else
    skip "could not list labels"
  fi

  # Rulesets first (readable without admin), then classic branch protection.
  if gh api "repos/$repo/rules/branches/$default" --jq '.[].type' 2> /dev/null | grep -qx pull_request; then
    ok "$default requires a pull request (ruleset)"
  elif gh api "repos/$repo/branches/$default/protection" --jq '.required_pull_request_reviews' 2> /dev/null | grep -q .; then
    ok "$default requires a pull request (branch protection)"
  else
    warn "$default does not require a pull request; anything with push access can bypass review"
  fi

  if gh api "repos/$repo/contents/$cfg?ref=$default" > /dev/null 2>&1; then
    ok "kit config is on $default"
  else
    warn "$cfg is not on $default yet; agent workflows read it from there, so merge the setup PR first"
  fi

  skip "Claude GitHub App: cannot be checked from here; confirm it lists $repo at https://github.com/settings/installations"
fi

# ---------------------------------------------------------------- summary
echo
if [ "$fails" -gt 0 ]; then
  echo "$fails problem(s), $warns warning(s). Fix the ✗ lines before labeling an issue agent:fix."
  exit 1
fi
echo "Ready. $warns warning(s)."
