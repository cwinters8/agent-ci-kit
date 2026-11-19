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
has() { [ -f ".github/workflows/$1.yml" ]; }  # is this kit workflow installed?
# Does any installed workflow mention $1? Decides which secrets and labels
# GitHub needs, so doctor follows the workflows rather than a fixed list.
# Captured first: `cat | grep -q` would close the pipe early and trip pipefail.
workflows_use() {
  local text
  text="$(cat .github/workflows/*.yml 2> /dev/null || true)"
  grep -qF -- "$1" <<< "$text"
}
codeowners=""
for f in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
  [ -f "$f" ] && { codeowners="$f"; break; }
done

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
  .github/actions/project-setup/action.yml; do
  if [ -f "$f" ]; then ok "$f"; else fail "$f missing"; fi
done
if has claude-fix-issue && [ ! -f .github/ISSUE_TEMPLATE/agent-fix.yml ]; then
  warn ".github/ISSUE_TEMPLATE/agent-fix.yml missing; issues for the fix agent will lack a repro"
fi
if [ ! -f .github/workflows/pr-checks.yml ]; then
  warn "no pr-checks.yml: fine only if your own CI runs commands.check on every PR, agent PRs included"
fi
for s in "${skills[@]}"; do
  [ -f ".claude/skills/$s/SKILL.md" ] || fail ".claude/skills/$s/SKILL.md missing"
done
agent_workflows=0
for w in .github/workflows/claude*.yml; do
  [ -f "$w" ] && agent_workflows=$((agent_workflows + 1))
done
if [ "$agent_workflows" -gt 0 ]; then
  ok "$agent_workflows agent workflow(s) in .github/workflows/"
else
  fail "no agent workflows (.github/workflows/claude*.yml)"
fi
# Code owner review is what stops an agent merging (docs/GUARDRAILS.md), and
# it needs someone to require.
if [ -z "$codeowners" ]; then
  fail ".github/CODEOWNERS missing; the merge gate's code owner review has no one to require"
elif ! grep -qE '^[^#]*@' "$codeowners"; then
  fail "$codeowners names no owner; the merge gate's code owner review has no one to require"
elif ! grep -qE '^[[:space:]]*(\*|/?\*\*(/\*)?)[[:space:]]+[^#[:space:]]*@' "$codeowners"; then
  fail "$codeowners has no catch-all owner, so a PR touching only unowned files needs no code owner review; add \"* @you\" as its first rule"
else
  # The last matching rule wins, so a rule with no owner after the catch-all
  # takes those paths out of code owner review.
  ownerless="$(awk '{ sub(/#.*/, "") } NF == 0 { next }
    $1 ~ /^(\*|\/?\*\*(\/\*)?)$/ && NF > 1 { catchall = 1; next }
    catchall && NF == 1 { print $1 }' "$codeowners")"
  if [ -n "$ownerless" ]; then
    fail "$codeowners has a rule with no owner after the catch-all ($(head -n 1 <<< "$ownerless")), so changes there need no code owner review; give it an owner"
  fi
fi
if [ -f CLAUDE.md ] && ! grep -q '@AGENTS.md' CLAUDE.md; then
  warn "CLAUDE.md does not import @AGENTS.md; Claude Code may not read the agent rules"
fi
if [ -f .claude/settings.json ] && ! jq empty .claude/settings.json 2> /dev/null; then
  fail ".claude/settings.json is not valid JSON; Claude Code will not load it"
elif [ -f .claude/settings.json ] && ! jq -e '[.hooks.SessionStart[]?.hooks[]?.command] | any(contains("session-start.sh"))' .claude/settings.json > /dev/null; then
  warn ".claude/settings.json does not run hooks/session-start.sh; cloud sessions will start without dependencies"
fi

# ---------------------------------------------------------------- config
section "Project config ($cfg)"
if [ ! -f "$cfg" ]; then
  skip "skipped: no config"
elif ! jq empty "$cfg" 2> /dev/null; then
  fail "$cfg is not valid JSON"
else
  # Mirrors the validation in .github/actions/project-setup/action.yml, so a
  # config that passes here also passes the setup step in CI. Keep them in step.
  errors="$(jq -r '
    def roles: ["install", "format", "lint", "typecheck", "test", "build", "check"];
    def list: if type == "array" then .[] else . end;
    def check: [.commands.check // empty | list];
    def granted: [.commands // {} | to_entries[] | select(.key != "install") | .value | list] + (.allow // []);
    def cmd: type == "string" and test("^[A-Za-z0-9 ._:/*=@+-]+$");
    def unknown($at; $known): (. // {}) | keys[] | select(. as $k | $known | index([$k]) | not)
      | "\($at)\(.): unknown field; expected one of \($known | join(", "))";
    [
      (if (.toolchain | type) != "object" then "toolchain: required; {} if the runner image already has what you need" else empty end),
      (if (.commands | type) != "object" then "commands: required" else empty end),
      unknown(""; ["$schema", "toolchain", "commands", "allow", "dependency_files", "protected_paths", "image"]),
      (.toolchain | unknown("toolchain."; ["go", "node", "python"])),
      (.toolchain.go | unknown("toolchain.go."; ["version_file"])),
      (.toolchain.node | unknown("toolchain.node."; ["version_file", "package_manager"])),
      (.toolchain.python | unknown("toolchain.python."; ["version_file"])),
      (.toolchain.node.package_manager // "npm" | select(IN("npm", "pnpm", "yarn") | not) | "toolchain.node.package_manager: \(tojson) is not npm, pnpm or yarn"),
      (.toolchain // {} | to_entries[] | select(.value | type != "object" or (.version_file | type != "string" or length == 0))
        | "toolchain.\(.key).version_file: required, the file that pins the version"),
      (.commands | unknown("commands."; roles)),
      (.commands.install | select(. != null and type != "string") | "commands.install: must be a string"),
      (.image | unknown("image."; ["inputs", "context", "dockerfile"])),
      (if .image == null then empty
       elif (.image | type) != "object" then "image: must be an object"
       elif (.image.inputs | type) != "array" or (.image.inputs | length) == 0 or any(.image.inputs[]; type != "string" or length == 0)
         then "image.inputs: required, a non-empty list of git pathspecs"
       else (.image | (.context, .dockerfile) | select(. != null and (type != "string" or length == 0))
         | "image.context and image.dockerfile must be non-empty strings")
       end),
      (if (check | length) == 0 then "commands.check: required, the gate CI and agents run before pushing" else empty end),
      (granted[] | select(cmd | not) | "not one plain command (no quotes or shell operators; wrap it in a Makefile target or package script): \(tojson)"),
      ((.protected_paths // [])[] | select(type != "string" or length == 0) | "protected_paths: entries must be non-empty strings"),
      (.dependency_files | select(. != null and (type != "array" or any(.[]; type != "string" or length == 0)))
        | "dependency_files: must be a list of non-empty strings")
    ] | .[]' "$cfg" 2> /dev/null)" || errors="a field has the wrong type (see docs/PROJECT-CONFIG.md)"
  if [ -n "$errors" ]; then
    while IFS= read -r e; do fail "$e"; done <<< "$errors"
  else
    ok "fields and commands valid"
  fi
  install="$(jq -r '.commands.install | if type == "string" then . else "" end' "$cfg" 2> /dev/null)"
  if [ -n "$install" ] && ! [[ "$install" =~ ^[A-Za-z0-9\ ._:/*=@+-]+$ ]]; then
    warn "commands.install is not one plain command, so agents cannot rerun it after a dependency change"
  fi

  while IFS= read -r vf; do
    [ -n "$vf" ] || continue
    if [ -f "$vf" ]; then ok "version file $vf exists"; else fail "toolchain version file $vf does not exist"; fi
  done < <(jq -r '.toolchain // {} | .[] | .version_file // empty' "$cfg")
  while IFS= read -r df; do
    [ -n "$df" ] || continue
    [ -e "$df" ] || warn "dependency file $df does not exist"
  done < <(jq -r '.dependency_files | arrays | .[] | strings' "$cfg" 2> /dev/null)
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
if [ -f .claude/project-profile.md ] && grep -q 'sample todo API' .claude/project-profile.md; then
  fail ".claude/project-profile.md still describes the kit's sample todo API"; leftover=1
fi
# Lists a workflow's `paths:` entries, one per line, without quotes.
path_filters() {
  awk '/^ *paths:/ { on = 1; next } on && /^ *(#|$)/ { next } on && /^ *- / { sub(/^ *- */, ""); gsub(/["'"'"']/, ""); print; next } on { exit }' "$1"
}
# A GitHub `paths:` glob as an ERE, per GitHub's filter cheat sheet: `**`
# spans directories, `*` stays within one, `?` and `+` make the preceding
# character optional or repeatable, and `[...]` is a character class.
glob_re() {
  # shellcheck disable=SC2016 # the $ is a literal regex character
  sed -e 's/[.^$(){}|\\]/\\&/g' -e 's#\*\*/#%DS%#g' -e 's#\*\*#%D%#g' \
    -e 's#\*#[^/]*#g' -e 's#%DS%#(.*/)?#g' -e 's#%D%#.*#g' \
    -e 's#^#^#' -e 's#$#$#' <<< "$1"
}
# Tracked source files per toolchain, captured whole: `git ls-files | grep -q`
# would close the pipe early and trip pipefail on a large repo.
stack_files() {
  case "$1" in
    go) git ls-files -- '*.go' ;;
    node) git ls-files -- '*.js' '*.mjs' '*.cjs' '*.jsx' '*.ts' '*.mts' '*.cts' '*.tsx' '*.vue' '*.svelte' ;;
    python) git ls-files -- '*.py' ;;
    # For `"toolchain": {}`, where the runner image has the runtime: any
    # language doctor knows.
    any)
      stack_files go
      stack_files node
      stack_files python
      git ls-files -- '*.rs' '*.rb' '*.java' '*.kt' '*.kts' '*.scala' '*.swift' '*.cs' '*.fs' \
        '*.php' '*.c' '*.h' '*.cc' '*.cpp' '*.hpp' '*.m' '*.mm' '*.ex' '*.exs' '*.erl' '*.clj' \
        '*.dart' '*.lua' '*.zig' '*.hs' '*.ml' '*.jl' '*.r' '*.R' '*.pl' '*.groovy'
      ;;
  esac
}
go_files="$(stack_files go)"
uses_go=1
if [ -z "$go_files" ]; then
  uses_go=0
  if [ -f "$cfg" ] && jq -e '.toolchain.go' "$cfg" > /dev/null 2>&1; then
    fail "$cfg sets up Go, but the repo has no Go files"; leftover=1
  fi
elif [ -f "$cfg" ] && ! jq -e '.toolchain.go' "$cfg" > /dev/null 2>&1; then
  uses_go=0
fi
for w in pr-checks build-image; do
  f=".github/workflows/$w.yml"
  [ -f "$f" ] || continue
  filters="$(path_filters "$f")"
  if grep -qxF '**.go' <<< "$filters" && [ "$uses_go" = 0 ]; then
    fail "$f paths: filter still lists the sample's Go files; point it at your source"; leftover=1
  fi
done
# Reads file paths on stdin; prints those a workflow's `paths:` filter would not
# trigger on. Patterns apply in order, as on GitHub: a `!` pattern drops what
# earlier ones matched, and a later positive pattern can bring it back.
untriggered() {
  local g r files hit=""
  files="$(cat)"
  [ -n "$files" ] || return 0
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    r="$(glob_re "${g#!}")" && [ -n "$r" ] || continue
    if [ "${g#!}" != "$g" ]; then
      hit="$(grep -vE "$r" <<< "$hit" || true)"
    else
      hit="$(printf '%s\n%s\n' "$hit" "$(grep -E "$r" <<< "$files" || true)" | sort -u)"
    fi
  done < <(path_filters "$1")
  comm -23 <(sort -u <<< "$files") <(sort -u <<< "$hit") | grep . || true
}
# Fails when a workflow's filter would skip a change to any of the given files.
check_triggers() {
  local missed
  missed="$(untriggered ".github/workflows/$1.yml" <<< "$3")"
  [ -n "$missed" ] || return 0
  fail "$1.yml paths: filter misses $(grep -c . <<< "$missed") of your $2 (e.g. $(head -n 1 <<< "$missed")); a change there would not run it"
  leftover=1
}
# pr-checks.yml must run for a change to any source file of a configured stack,
# and to anything else that changes what the checks do: the kit config, the
# setup action, the workflow itself and the dependency files.
if [ -f .github/workflows/pr-checks.yml ] && [ -f "$cfg" ]; then
  stacks="$(jq -r '.toolchain // {} | keys[]' "$cfg" 2> /dev/null || true)"
  for stack in $stacks; do
    check_triggers pr-checks "$stack files" "$(stack_files "$stack")"
  done
  if [ -z "$stacks" ]; then
    src="$(stack_files any)"
    if [ -n "$src" ]; then
      check_triggers pr-checks "source files" "$src"
    else
      warn "no source files in a language doctor knows; check that pr-checks.yml paths: covers yours"
    fi
  fi
  check_triggers pr-checks "config, setup and dependency files" "$(
    find "$cfg" .github/workflows/pr-checks.yml .github/actions/project-setup -type f 2> /dev/null
    jq -r '.dependency_files | arrays | .[] | strings' "$cfg" 2> /dev/null | while IFS= read -r df; do
      [ -f "$df" ] && echo "$df"
    done
  )"
fi
if [ -f .github/workflows/build-image.yml ]; then
  dockerfile="$(jq -r '.image.dockerfile // "Dockerfile"' "$cfg" 2> /dev/null || echo Dockerfile)"
  if [ ! -f "$dockerfile" ]; then
    fail "build-image.yml is present but $dockerfile is not; delete the workflow if you ship no image"; leftover=1
  elif [ -f "$cfg" ] && ! jq -e '.image' "$cfg" > /dev/null 2>&1; then
    fail "build-image.yml is present but $cfg has no image section"; leftover=1
  else
    context="$(jq -r '.image.context // "."' "$cfg" 2> /dev/null || echo .)"
    case "$context" in
      *://* | git@*) ;;
      *) [ -d "$context" ] || { fail "image.context $context is not a directory; every image build would fail"; leftover=1; } ;;
    esac
    # A change to the image config or the workflow must rebuild too.
    check_triggers build-image "image config files" "$(find "$cfg" .github/workflows/build-image.yml -type f 2> /dev/null)"
    # build-image.yml must run for a change to anything that goes into the image.
    # Untracked files count too: doctor runs before the setup commit.
    inputs=()
    while IFS= read -r i; do
      [ -n "$i" ] || continue
      inputs+=("$i")
      case "$i" in ':!'* | ':^'* | ':(exclude'*) continue ;; esac
      if [ -z "$(git ls-files --cached --others --exclude-standard -- "$i" 2> /dev/null)" ]; then
        fail "image.inputs entry $i matches no files; the image hash would leave out what it was meant to cover"; leftover=1
      fi
    done < <(jq -r '.image.inputs // [] | .[]' "$cfg" 2> /dev/null)
    if [ "${#inputs[@]}" -gt 0 ]; then
      selected="$(git ls-files --cached --others --exclude-standard -- "${inputs[@]}" 2> /dev/null || true)"
      # The Dockerfile shapes the image, so it belongs in the hash.
      if ! grep -qxF -- "${dockerfile#./}" <<< "$selected"; then
        fail "image.inputs does not select $dockerfile, so a change to it would reuse the old image"; leftover=1
      fi
      check_triggers build-image "image input files" "$selected"
    fi
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

  # Every non-local action the installed workflows use, as owner/repo@ref.
  used="$(cat .github/workflows/*.yml .github/actions/*/action.yml 2> /dev/null \
    | sed -nE 's/^[[:space:]-]*uses:[[:space:]]*([^[:space:]#]+).*/\1/p' | grep -v '^\.' | sort -u || true)"
  if perms="$(gh api "repos/$repo/actions/permissions" 2> /dev/null)"; then
    allowed="$(jq -r '.allowed_actions // "all"' <<< "$perms")"
    unpinned="$(grep -vE '@[0-9a-f]{40}$' <<< "$used" | grep . || true)"
    if [ "$(jq -r '.sha_pinning_required // false' <<< "$perms")" = true ] && [ -n "$unpinned" ]; then
      fail "Actions policy requires actions pinned to a commit SHA, but the workflows use tags ($(head -n 1 <<< "$unpinned"), $(grep -c . <<< "$unpinned") in all); pin them or turn the policy off"
    fi
    if [ "$(jq -r .enabled <<< "$perms")" != true ]; then
      fail "GitHub Actions is disabled for this repo"
    elif [ "$allowed" = local_only ]; then
      fail "Actions policy allows only local actions; the kit needs anthropics/claude-code-action and others"
    elif [ "$allowed" = selected ]; then
      if sel="$(gh api "repos/$repo/actions/permissions/selected-actions" 2> /dev/null)"; then
        blocked=()
        while IFS= read -r a; do
          [ -n "$a" ] || continue
          [ "${a%%/*}" = actions ] && [ "$(jq -r .github_owned_allowed <<< "$sel")" = true ] && continue
          hit=0
          while IFS= read -r pat; do
            [ -n "$pat" ] && grep -qE "$(glob_re "$pat")" <<< "$a" && { hit=1; break; }
          done < <(jq -r '.patterns_allowed // [] | .[]' <<< "$sel")
          [ "$hit" = 1 ] || blocked+=("$a")
        done <<< "$used"
        if [ "${#blocked[@]}" = 0 ]; then
          ok "Actions policy allows every action the kit uses"
        elif [ "$(jq -r .verified_allowed <<< "$sel")" = true ]; then
          warn "Actions policy may block ${blocked[*]} (allowed only if from a verified creator); add them to the allowed list"
        else
          fail "Actions policy blocks ${blocked[*]}; add them under Settings > Actions > General"
        fi
      else
        warn "Actions allows only selected actions, and the list could not be read; make sure the kit's actions are on it"
      fi
    else
      ok "GitHub Actions enabled"
    fi
  else
    skip "could not read Actions settings (needs admin)"
  fi

  if secrets="$(gh api "repos/$repo/actions/secrets" --paginate --jq '.secrets[].name' 2> /dev/null)"; then
    if grep -qxE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' <<< "$secrets"; then
      ok "Claude credential secret set"
    else
      fail "no CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY secret"
    fi
    if ! workflows_use secrets.AGENT_PR_TOKEN; then
      :
    elif grep -qx AGENT_PR_TOKEN <<< "$secrets"; then
      ok "AGENT_PR_TOKEN secret set"
    else
      fail "no AGENT_PR_TOKEN secret; CI will not run on agent PRs"
    fi
  else
    skip "could not list secrets (needs admin); check Settings > Secrets and variables > Actions"
  fi

  if ! workflows_use agent:fix; then
    :
  elif have="$(gh api "repos/$repo/labels" --paginate --jq '.[].name' 2> /dev/null)"; then
    missing=()
    for l in "${labels[@]}"; do grep -qxF "$l" <<< "$have" || missing+=("$l"); done
    if [ "${#missing[@]}" = 0 ]; then ok "agent labels exist"; else fail "missing labels: ${missing[*]}"; fi
  else
    skip "could not list labels"
  fi

  # A profile that permits review-sweep's reaction-count approval shortcut is
  # only safe on a private repo with a single maintainer.
  if [ -f .claude/project-profile.md ] && grep -q 'approval shortcut is' .claude/project-profile.md; then
    visibility="$(jq -r .visibility <<< "$info")"
    if [ "$visibility" != private ]; then
      fail "project profile permits review-sweep's reaction-count approval shortcut, but the repo is $visibility; remove that line"
    elif people="$(gh api "repos/$repo/collaborators" --paginate --jq '.[].login' 2> /dev/null)"; then
      if [ "$(grep -c . <<< "$people")" -gt 1 ]; then
        fail "project profile permits review-sweep's reaction-count approval shortcut, but the repo has more than one collaborator; remove that line"
      fi
    else
      warn "project profile permits review-sweep's reaction-count approval shortcut; keep it only if you are the sole maintainer"
    fi
  fi

  # The merge gate (README Quickstart step 5): a pull request with an approval
  # and code owner review. The agent is never a code owner, so it cannot merge
  # its own work, whatever commands it manages to run. Rulesets first
  # (readable without admin), then classic branch protection.
  owner="${repo%%/*}"
  # One path segment, even for a branch like release/main.
  branch="$(jq -rn --arg b "$default" '$b | @uri')"
  rules="$(gh api "repos/$repo/rules/branches/$branch" 2> /dev/null || echo '[]')"
  gate="$(jq -c 'def strong: (.required_approving_review_count // 0) >= 1 and .require_code_owner_review == true;
    def fresh: .dismiss_stale_reviews_on_push == true or .require_last_push_approval == true;
    [.[] | select(.type == "pull_request") | .parameters + {ruleset_id: .ruleset_id}]
    | (map(select(strong and fresh)) + map(select(strong)) + .) | first // empty' <<< "$rules" 2> /dev/null || true)"
  via=ruleset
  if [ -z "$gate" ]; then
    via="branch protection"
    gate="$(gh api "repos/$repo/branches/$branch/protection" --jq '.required_pull_request_reviews // empty
      | {required_approving_review_count, require_code_owner_review: .require_code_owner_reviews,
         dismiss_stale_reviews_on_push: .dismiss_stale_reviews, require_last_push_approval,
         bypass_apps: [.bypass_pull_request_allowances.apps // [] | .[] | .slug]}' 2> /dev/null || true)"
  fi
  if [ -z "$gate" ]; then
    fail "$default does not require a pull request; set up the ruleset in README Quickstart step 5 (private repos need GitHub Pro or a paid org)"
  elif ! jq -e '(.required_approving_review_count // 0) >= 1 and .require_code_owner_review == true' <<< "$gate" > /dev/null; then
    fail "$default requires a pull request but not an approval with code owner review; nothing stops an agent merging its own PR (docs/GUARDRAILS.md)"
  else
    ok "$default requires a code owner's approval ($via)"
    if ! jq -e '.dismiss_stale_reviews_on_push == true or .require_last_push_approval == true' <<< "$gate" > /dev/null; then
      fail "$default keeps an approval after new pushes, so an agent push after your approval needs no review; turn on \"Require approval of the most recent reviewable push\""
    fi
    apps="$(jq -r '.bypass_apps // [] | join(", ")' <<< "$gate")"
    if [ -n "$apps" ]; then
      fail "$default branch protection lets these apps skip the pull request rule: $apps; an agent acting as one could merge. Remove them"
    fi
    id="$(jq -r '.ruleset_id // empty' <<< "$gate")"
    if [ -n "$id" ] && bypass="$(gh api "repos/$repo/rulesets/$id" --jq '.bypass_actors // empty' 2> /dev/null)" && [ -n "$bypass" ]; then
      if jq -e 'any(.[]; .actor_type == "Integration")' <<< "$bypass" > /dev/null; then
        fail "the $default ruleset lets a GitHub App bypass it; an agent acting as that app could merge. Keep only the Repository admin role"
      elif ! jq -e 'any(.[]; .actor_type == "RepositoryRole" and .actor_id == 5)' <<< "$bypass" > /dev/null; then
        warn "the $default ruleset has no Repository admin bypass; agent PRs are opened as you, so you cannot approve or merge them"
      fi
    fi
  fi

  if [ -n "$codeowners" ] && [ "$owner" != cwinters8 ] && grep -qE '^[^#]*@cwinters8([[:space:]]|$)' "$codeowners"; then
    fail "$codeowners still names the kit's author (@cwinters8); put your handle or team there"
  fi
  if [ -n "$codeowners" ]; then
    if ! gh api "repos/$repo/contents/$codeowners?ref=$branch" > /dev/null 2>&1; then
      warn "$codeowners is not on $default yet; code owner review takes effect once the setup PR merges"
    elif errs="$(gh api "repos/$repo/codeowners/errors?ref=$branch" --jq '.errors[] | "line \(.line): \(.message)"' 2> /dev/null)" && [ -n "$errs" ]; then
      fail "GitHub rejects $codeowners: $(head -n 1 <<< "$errs")"
    fi
  fi

  if gh api "repos/$repo/contents/$cfg?ref=$branch" > /dev/null 2>&1; then
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
