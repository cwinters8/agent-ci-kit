#!/usr/bin/env bash
# Regression tests for setup/install.sh and setup/adopt-kit/doctor.sh. Each
# case builds a scratch repo from this kit's files and checks what doctor
# reports. Only the local checks are covered: the GitHub section needs a real
# repo and credentials. Run with `make test-setup` (part of `make check`).
set -euo pipefail

kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
doctor="$kit/setup/adopt-kit/doctor.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { printf 'ok   %s\n' "$1"; }
flunk() { printf 'FAIL %s\n%s\n' "$1" "${2:-}" | sed '2,$s/^/     /'; failures=$((failures + 1)); }

# expect NAME OUTPUT [+]LINE... : each +LINE must appear in OUTPUT, each -LINE must not.
expect() {
  local name="$1" out="$2" want
  shift 2
  for want in "$@"; do
    case "$want" in
      +*) grep -qF -- "${want#+}" <<< "$out" || { flunk "$name" "missing: ${want#+}"$'\n'"$out"; return; } ;;
      -*) ! grep -qF -- "${want#-}" <<< "$out" || { flunk "$name" "unexpected: ${want#-}"$'\n'"$out"; return; } ;;
    esac
  done
  pass "$name"
}

# A scratch repo holding the kit files (not the sample app), no remote.
kit_repo() {
  local dir="$tmp/$1"
  mkdir -p "$dir"
  (cd "$kit" && git ls-files -z .github .claude AGENTS.md CLAUDE.md docs | tar --null -T - -cf -) | tar -xf - -C "$dir"
  git -C "$dir" init -q
  echo "$dir"
}

# A kit repo rewritten for a small Node project.
node_repo() {
  local dir
  dir="$(kit_repo "$1")"
  (
    cd "$dir"
    echo 22 > .nvmrc
    echo '{"name":"x","private":true,"scripts":{"check":"node --test"}}' > package.json
    echo '{}' > package-lock.json
    mkdir -p src && echo 'export const x = 1;' > src/x.js
    cat > .claude/agent-ci.json << 'EOF'
{
  "toolchain": { "node": { "version_file": ".nvmrc", "package_manager": "npm" } },
  "commands": { "install": "npm ci", "check": "npm run check" },
  "dependency_files": ["package.json", "package-lock.json"]
}
EOF
    printf '# Agent guide\n\nA tiny Node service.\n' > AGENTS.md
    printf '# Project profile\n\n## Repo\n\nPublic repo.\n' > .claude/project-profile.md
    echo '* @acme' > .github/CODEOWNERS
    rm .github/workflows/build-image.yml
    sed -e "s#- '\*\*\.go'#- 'src/**'#" -e '/- go\.mod/d' -e '/- go\.sum/d' -e "s#- Makefile#- 'package*.json'#" \
      .github/workflows/pr-checks.yml > pr-checks.tmp && mv pr-checks.tmp .github/workflows/pr-checks.yml
    git add -A
  )
  echo "$dir"
}

run_doctor() { (cd "$1" && bash "$doctor" 2>&1) || true; }

# Leaves claude.yml as the only agent workflow, however many the kit ships.
only_claude_yml() { find "$1/.github/workflows" -name 'claude?*.yml' ! -name claude.yml -delete; }

# A stand-in for `gh api PATH [--paginate] [--jq EXPR]` that answers from JSON
# files in $FAKE_GH_DIR (PATH with / as _, query string dropped) and fails like
# a 404 when there is none. Lets the GitHub checks run without a network.
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat > "$fakebin/gh" << 'FAKE'
#!/usr/bin/env bash
[ "${1:-}" = api ] || exit 1
path="${2%%\?*}"
shift 2
expr=.
while [ $# -gt 0 ]; do
  case "$1" in --jq) expr="$2"; shift 2 ;; *) shift ;; esac
done
f="$FAKE_GH_DIR/$(tr / _ <<< "$path").json"
[ -f "$f" ] || { echo "HTTP 404: Not Found" >&2; exit 1; }
jq -r "$expr" "$f"
FAKE
chmod +x "$fakebin/gh"

# A healthy acme/app as GitHub would report it; each test breaks one piece.
github_ok() {
  local d="$tmp/gh-$1"
  mkdir -p "$d"
  echo '{"default_branch": "main", "visibility": "private"}' > "$d/repos_acme_app.json"
  echo '{"enabled": true, "allowed_actions": "all"}' > "$d/repos_acme_app_actions_permissions.json"
  echo '{"secrets": [{"name": "CLAUDE_CODE_OAUTH_TOKEN"}, {"name": "AGENT_PR_TOKEN"}]}' > "$d/repos_acme_app_actions_secrets.json"
  echo '[{"name": "agent:fix"}, {"name": "agent:fix-opus"}, {"name": "agent:needs-human"}, {"name": "agent:large-diff"}]' > "$d/repos_acme_app_labels.json"
  echo '[{"type": "pull_request", "ruleset_id": 7, "parameters": {"required_approving_review_count": 1, "require_code_owner_review": true, "require_last_push_approval": true}}]' > "$d/repos_acme_app_rules_branches_main.json"
  echo '{"bypass_actors": [{"actor_type": "RepositoryRole", "actor_id": 5, "bypass_mode": "always"}]}' > "$d/repos_acme_app_rulesets_7.json"
  echo '{}' > "$d/repos_acme_app_contents_.claude_agent-ci.json.json"
  echo '{}' > "$d/repos_acme_app_contents_.github_CODEOWNERS.json"
  echo '{"errors": []}' > "$d/repos_acme_app_codeowners_errors.json"
  echo "$d"
}
github_doctor() { (cd "$1" && FAKE_GH_DIR="$2" PATH="$fakebin:$PATH" bash "$doctor" acme/app 2>&1) || true; }

# ------------------------------------------------------------------ install.sh
cfgdir="$tmp/claude-config"
out="$(CLAUDE_CONFIG_DIR="$cfgdir" bash "$kit/setup/install.sh" 2>&1)"
dest="$cfgdir/skills/adopt-kit"
if [ -f "$dest/SKILL.md" ] && [ -f "$dest/doctor.sh" ] && [ "$(cat "$dest/kit-path")" = "$kit" ]; then
  pass "install: fresh install copies the skill and records the kit path"
else
  flunk "install: fresh install" "$out"
fi

echo stale > "$dest/stale-file"
if CLAUDE_CONFIG_DIR="$cfgdir" bash "$kit/setup/install.sh" > /dev/null 2>&1 \
  && [ ! -e "$dest/stale-file" ] && [ -f "$dest/.installed-by-agent-ci-kit" ] \
  && [ -z "$(find "$cfgdir/skills" -maxdepth 1 -name '.adopt-kit.*')" ]; then
  pass "install: re-run replaces its own install and leaves no staging dirs"
else
  flunk "install: re-run"
fi

# A stand-in mv that fails the swap's second step, as an interrupt there would.
failmv="$tmp/failmv"
mkdir -p "$failmv"
# shellcheck disable=SC2016 # the stand-in expands $1 and $@ itself
printf '#!/usr/bin/env bash\ncase "$1" in *.adopt-kit.new.*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v mv)" > "$failmv/mv"
chmod +x "$failmv/mv"
echo keep > "$dest/old-marker"
if ! CLAUDE_CONFIG_DIR="$cfgdir" PATH="$failmv:$PATH" bash "$kit/setup/install.sh" > /dev/null 2>&1 \
  && [ -f "$dest/old-marker" ] && [ -z "$(find "$cfgdir/skills" -maxdepth 1 -name '.adopt-kit.*')" ]; then
  pass "install: an update that fails mid-swap restores the previous install"
else
  flunk "install: interrupted swap"
fi
rm -f "$dest/old-marker"

foreign="$tmp/foreign-config"
mkdir -p "$foreign/skills/adopt-kit" && echo mine > "$foreign/skills/adopt-kit/SKILL.md"
if ! CLAUDE_CONFIG_DIR="$foreign" bash "$kit/setup/install.sh" > /dev/null 2>&1 \
  && [ "$(cat "$foreign/skills/adopt-kit/SKILL.md")" = mine ]; then
  pass "install: refuses to replace a directory it did not create"
else
  flunk "install: foreign directory"
fi

# ------------------------------------------------------------------ doctor.sh
out="$(run_doctor "$(kit_repo sample)")"
expect "doctor: flags the sample's project text" "$out" \
  "+✗ AGENTS.md project sections still describe the kit's sample todo API" \
  "+✗ .claude/project-profile.md still describes the kit's sample todo API"

dir="$(node_repo good)"
out="$(run_doctor "$dir")"
expect "doctor: a filled-in Node setup passes the local checks" "$out" \
  "+✓ fields and commands valid" "+✓ nothing left over from the sample project" \
  "-✗ AGENTS.md" "-✗ .claude/" "-✗ .github/"

dir="$(node_repo go-config)"
cp "$kit/.claude/agent-ci.json" "$dir/.claude/agent-ci.json"
cp "$kit/.github/workflows/pr-checks.yml" "$dir/.github/workflows/"
out="$(run_doctor "$dir")"
expect "doctor: flags the sample's Go config and filters in a Node repo" "$out" \
  "+sets up Go, but the repo has no Go files" \
  "+pr-checks.yml paths: filter still lists the sample's Go files"

dir="$(node_repo mixed)"
echo 'package main' > "$dir/main.go"
jq '.toolchain.go = {"version_file": "go.mod"}' "$dir/.claude/agent-ci.json" > "$dir/cfg" && mv "$dir/cfg" "$dir/.claude/agent-ci.json"
echo 'module x' > "$dir/go.mod"
cp "$kit/.github/workflows/pr-checks.yml" "$dir/.github/workflows/"
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: flags Go-only filters in a Go and Node repo" "$out" \
  "+pr-checks.yml paths: filter misses 1 of your node files (e.g. src/x.js)" "-of your go files"

printf "    paths:\n      - '**.go'\n      - go.mod\n      - package.json\n" > "$dir/filters"
sed -e '/^    paths:/,/^[^ ]/{/^    paths:/r '"$dir/filters"'
/^ *- /d;/^    paths:/d;}' "$kit/.github/workflows/pr-checks.yml" > "$dir/.github/workflows/pr-checks.yml"
rm "$dir/filters"
out="$(run_doctor "$dir")"
expect "doctor: a manifest alone does not count as covering a stack's sources" "$out" \
  "+pr-checks.yml paths: filter misses 1 of your node files"

dir="$(node_repo uncovered-dir)"
mkdir -p "$dir/scripts" && echo 'console.log(1)' > "$dir/scripts/build.js"
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: every source directory must be covered, not just one" "$out" \
  "+pr-checks.yml paths: filter misses 1 of your node files (e.g. scripts/build.js)"

dir="$(node_repo image-inputs)"
mkdir -p "$dir/assets" && echo logo > "$dir/assets/logo.txt"
printf 'FROM scratch\nCOPY src assets /\n' > "$dir/Dockerfile"
jq '.image = {"inputs": ["src", "assets", "web"], "context": "app"}' "$dir/.claude/agent-ci.json" > "$dir/cfg" && mv "$dir/cfg" "$dir/.claude/agent-ci.json"
sed -e "s#- '\*\*\.go'#- 'src/**'#" -e '/- go\.mod/d' -e '/- go\.sum/d' -e '/- \.claude\/agent-ci\.json/d' \
  "$kit/.github/workflows/build-image.yml" > "$dir/.github/workflows/build-image.yml"
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: build-image.yml must fire for every image input" "$out" \
  "+build-image.yml paths: filter misses 1 of your image input files (e.g. assets/logo.txt)" "-src/x.js" \
  "+✗ image.inputs entry web matches no files" "-entry src matches" \
  "+✗ image.inputs does not select Dockerfile" "+✗ image.context app is not a directory" \
  "+build-image.yml paths: filter misses 1 of your image config files (e.g. .claude/agent-ci.json)"

dir="$(node_repo reinclude)"
mkdir -p "$dir/generated/checked"
echo 'export const a = 1;' > "$dir/generated/checked/a.js"
echo 'export const b = 1;' > "$dir/generated/b.js"
sed -e "s#- 'src/\*\*'#- '**'\\
      - '!generated/**'\\
      - 'generated/checked/**'#" "$dir/.github/workflows/pr-checks.yml" > "$dir/w" && mv "$dir/w" "$dir/.github/workflows/pr-checks.yml"
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: filters apply in order, so a later pattern can re-include a path" "$out" \
  "+pr-checks.yml paths: filter misses 1 of your node files (e.g. generated/b.js)"

dir="$(node_repo no-toolchain)"
mkdir -p "$dir/crates" && echo 'fn main() {}' > "$dir/crates/main.rs"
jq '.toolchain = {}' "$dir/.claude/agent-ci.json" > "$dir/cfg" && mv "$dir/cfg" "$dir/.claude/agent-ci.json"
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: with an empty toolchain, every known source file must trigger pr-checks" "$out" \
  "+pr-checks.yml paths: filter misses 1 of your source files (e.g. crates/main.rs)"

dir="$(node_repo optional-char)"
echo 'export const y = 1;' > "$dir/src/x1.js"
sed -e "s#- 'src/\*\*'#- 'src/xy?.js'#" "$dir/.github/workflows/pr-checks.yml" > "$dir/w" && mv "$dir/w" "$dir/.github/workflows/pr-checks.yml"
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: ? in a filter makes the preceding character optional, as on GitHub" "$out" \
  "+pr-checks.yml paths: filter misses 1 of your node files (e.g. src/x1.js)"

dir="$(node_repo partial-owners)"
echo '/docs/ @acme' > "$dir/.github/CODEOWNERS"
out="$(run_doctor "$dir")"
expect "doctor: CODEOWNERS without a catch-all owner fails" "$out" "+✗ .github/CODEOWNERS has no catch-all owner"

dir="$(node_repo ownerless-rule)"
printf '* @acme\n/apps/github\n' > "$dir/.github/CODEOWNERS"
out="$(run_doctor "$dir")"
expect "doctor: a rule with no owner after the catch-all fails" "$out" \
  "+✗ .github/CODEOWNERS has a rule with no owner after the catch-all (/apps/github)"

dir="$(node_repo lockfile)"
sed -e "s#- 'package\*.json'#- package.json#" "$dir/.github/workflows/pr-checks.yml" > "$dir/w" \
  && mv "$dir/w" "$dir/.github/workflows/pr-checks.yml"
out="$(run_doctor "$dir")"
expect "doctor: pr-checks.yml must fire for dependency and config files too" "$out" \
  "+pr-checks.yml paths: filter misses 1 of your config, setup and dependency files (e.g. package-lock.json)"

dir="$(kit_repo big-go)"
for i in $(seq 1 4000); do echo "package p" > "$dir/file_with_a_long_enough_name_$i.go"; done
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: a large Go repo is not mistaken for one without Go files" "$out" \
  "-has no Go files" "-filter still lists the sample's Go files"

dir="$(node_repo store-layout)"
printf '# Project profile\n\nHandlers call internal/store for persistence.\n' > "$dir/.claude/project-profile.md"
out="$(run_doctor "$dir")"
expect "doctor: a profile that mentions internal/store is not mistaken for the sample" "$out" \
  "-.claude/project-profile.md still describes"

dir="$(node_repo bad-types)"
echo '{"toolchain": [], "commands": "x"}' > "$dir/.claude/agent-ci.json"
out="$(run_doctor "$dir")"
expect "doctor: a config with wrong types fails instead of passing" "$out" \
  "+✗ a field has the wrong type" "-✓ fields and commands valid"

dir="$(node_repo install-number)"
jq '.commands.install = 123' "$dir/.claude/agent-ci.json" > "$dir/cfg" && mv "$dir/cfg" "$dir/.claude/agent-ci.json"
out="$(run_doctor "$dir")"
expect "doctor: a non-string install command fails" "$out" \
  "+✗ commands.install: must be a string" "-✓ fields and commands valid"

dir="$(node_repo deps-string)"
jq '.dependency_files = "package.json"' "$dir/.claude/agent-ci.json" > "$dir/cfg" && mv "$dir/cfg" "$dir/.claude/agent-ci.json"
out="$(run_doctor "$dir")"
expect "doctor: dependency_files that is not a list fails" "$out" \
  "+✗ dependency_files: must be a list of non-empty strings" "-✓ fields and commands valid"

dir="$(node_repo bad-fields)"
cat > "$dir/.claude/agent-ci.json" << 'EOF'
{"toolchain": {"node": {"version_file": ".nvmrc"}}, "protect_paths": ["db/"],
 "commands": {"install": "npm ci && npm run build", "check": ["npm test && rm -rf /"], "deploy": "x"},
 "image": {"context": "."}}
EOF
out="$(run_doctor "$dir")"
expect "doctor: mirrors the setup action's field checks" "$out" \
  "+✗ protect_paths: unknown field" "+✗ commands.deploy: unknown field" \
  "+✗ image.inputs: required" "+✗ not one plain command" \
  "+! commands.install is not one plain command"

dir="$(node_repo bad-settings)"
echo '{"hooks": {"SessionStart": [' > "$dir/.claude/settings.json"
echo '"session-start.sh"' >> "$dir/.claude/settings.json"
out="$(run_doctor "$dir")"
expect "doctor: malformed .claude/settings.json fails" "$out" \
  "+✗ .claude/settings.json is not valid JSON"

dir="$(node_repo claude-only)"
only_claude_yml "$dir"
rm "$dir/.github/ISSUE_TEMPLATE/agent-fix.yml"
out="$(run_doctor "$dir")"
expect "doctor: the fix workflow's files are optional when it is not installed" "$out" \
  "+✓ 1 agent workflow(s)" "-agent-fix.yml"

# ------------------------------------------------------------------ doctor.sh, GitHub side
repo_dir="$(node_repo github)"
out="$(github_doctor "$repo_dir" "$(github_ok healthy)")"
expect "doctor: a healthy repo passes the GitHub checks" "$out" \
  "+✓ main requires a code owner's approval (ruleset)" "+✓ agent labels exist" "+✓ AGENT_PR_TOKEN secret set" \
  "+Ready." "-✗"

gh_dir="$(github_ok weak-gate)"
echo '[{"type": "pull_request", "ruleset_id": 7, "parameters": {"required_approving_review_count": 0, "require_code_owner_review": false}}]' \
  > "$gh_dir/repos_acme_app_rules_branches_main.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: a pull request rule without code owner review fails" "$out" \
  "+✗ main requires a pull request but not an approval with code owner review"

gh_dir="$(github_ok stale-approval)"
echo '[{"type": "pull_request", "ruleset_id": 7, "parameters": {"required_approving_review_count": 1, "require_code_owner_review": true, "dismiss_stale_reviews_on_push": false, "require_last_push_approval": false}}]' \
  > "$gh_dir/repos_acme_app_rules_branches_main.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: an approval that survives later pushes fails" "$out" \
  "+✗ main keeps an approval after new pushes"

gh_dir="$(github_ok sha-pinning)"
echo '{"enabled": true, "allowed_actions": "all", "sha_pinning_required": true}' > "$gh_dir/repos_acme_app_actions_permissions.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: a SHA-pinning policy fails while the workflows use tags" "$out" \
  "+✗ Actions policy requires actions pinned to a commit SHA"

gh_dir="$(github_ok slash-branch)"
echo '{"default_branch": "release/main", "visibility": "private"}' > "$gh_dir/repos_acme_app.json"
mv "$gh_dir/repos_acme_app_rules_branches_main.json" "$gh_dir/repos_acme_app_rules_branches_release%2Fmain.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: a default branch with a slash is one path segment" "$out" \
  "+✓ release/main requires a code owner's approval (ruleset)"

gh_dir="$(github_ok no-gate)"
echo '[]' > "$gh_dir/repos_acme_app_rules_branches_main.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: no merge gate at all fails" "$out" "+✗ main does not require a pull request"

gh_dir="$(github_ok classic)"
echo '[]' > "$gh_dir/repos_acme_app_rules_branches_main.json"
echo '{"required_pull_request_reviews": {"required_approving_review_count": 1, "require_code_owner_reviews": true, "dismiss_stale_reviews": true}}' \
  > "$gh_dir/repos_acme_app_branches_main_protection.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: classic branch protection with code owner review passes" "$out" \
  "+✓ main requires a code owner's approval (branch protection)" "-keeps an approval"

gh_dir="$(github_ok classic-app-bypass)"
echo '[]' > "$gh_dir/repos_acme_app_rules_branches_main.json"
echo '{"required_pull_request_reviews": {"required_approving_review_count": 1, "require_code_owner_reviews": true, "require_last_push_approval": true, "bypass_pull_request_allowances": {"users": [], "teams": [], "apps": [{"slug": "claude"}]}}}' \
  > "$gh_dir/repos_acme_app_branches_main_protection.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: branch protection an app can bypass fails" "$out" \
  "+✗ main branch protection lets these apps skip the pull request rule: claude"

gh_dir="$(github_ok app-bypass)"
echo '{"bypass_actors": [{"actor_type": "Integration", "actor_id": 1234, "bypass_mode": "always"}]}' \
  > "$gh_dir/repos_acme_app_rulesets_7.json"
out="$(github_doctor "$repo_dir" "$gh_dir")"
expect "doctor: a ruleset an app can bypass fails" "$out" "+✗ the main ruleset lets a GitHub App bypass it"

dir="$(node_repo kit-owner)"
echo '* @cwinters8' > "$dir/.github/CODEOWNERS"
out="$(github_doctor "$dir" "$(github_ok kit-owner)")"
expect "doctor: CODEOWNERS still naming the kit author fails" "$out" \
  "+✗ .github/CODEOWNERS still names the kit's author"

dir="$(node_repo no-codeowners)"
rm "$dir/.github/CODEOWNERS"
out="$(run_doctor "$dir")"
expect "doctor: a missing CODEOWNERS fails" "$out" "+✗ .github/CODEOWNERS missing"

gh_dir="$(github_ok big-workflow)"
echo '{"secrets": [{"name": "ANTHROPIC_API_KEY"}]}' > "$gh_dir/repos_acme_app_actions_secrets.json"
dir="$(node_repo big-workflow)"
{ printf '# '; head -c 2000000 /dev/zero | tr '\0' x; echo; } >> "$dir/.github/workflows/claude-fix-issue.yml"
out="$(github_doctor "$dir" "$gh_dir")"
expect "doctor: large workflow files still count as using AGENT_PR_TOKEN" "$out" "+✗ no AGENT_PR_TOKEN secret"

gh_dir="$(github_ok claude-only)"
echo '{"secrets": [{"name": "ANTHROPIC_API_KEY"}]}' > "$gh_dir/repos_acme_app_actions_secrets.json"
echo '[]' > "$gh_dir/repos_acme_app_labels.json"
dir="$(node_repo gh-claude-only)"
only_claude_yml "$dir"
out="$(github_doctor "$dir" "$gh_dir")"
expect "doctor: secrets and labels follow the installed workflows" "$out" \
  "+✓ Claude credential secret set" "-AGENT_PR_TOKEN" "-missing labels"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures setup test(s) failed"
  exit 1
fi
echo "setup tests passed"
