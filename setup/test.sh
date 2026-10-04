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
    rm .github/workflows/build-image.yml
    sed -e "s#- '\*\*\.go'#- 'src/**'#" -e '/- go\.mod/d' -e '/- go\.sum/d' -e 's#- Makefile#- package.json#' \
      .github/workflows/pr-checks.yml > pr-checks.tmp && mv pr-checks.tmp .github/workflows/pr-checks.yml
    git add -A
  )
  echo "$dir"
}

run_doctor() { (cd "$1" && bash "$doctor" 2>&1) || true; }

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
jq '.image = {"inputs": ["src", "assets", "Dockerfile"]}' "$dir/.claude/agent-ci.json" > "$dir/cfg" && mv "$dir/cfg" "$dir/.claude/agent-ci.json"
sed -e "s#- '\*\*\.go'#- 'src/**'#" -e '/- go\.mod/d' -e '/- go\.sum/d' \
  "$kit/.github/workflows/build-image.yml" > "$dir/.github/workflows/build-image.yml"
git -C "$dir" add -A
out="$(run_doctor "$dir")"
expect "doctor: build-image.yml must fire for every image input" "$out" \
  "+build-image.yml paths: filter misses 1 of your image input files (e.g. assets/logo.txt)" "-src/x.js"

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
rm "$dir/.github/workflows/claude-fix-issue.yml" "$dir/.github/workflows/claude-review-sweep.yml" \
  "$dir/.github/ISSUE_TEMPLATE/agent-fix.yml"
out="$(run_doctor "$dir")"
expect "doctor: the fix workflow's files are optional when it is not installed" "$out" \
  "+✓ 1 agent workflow(s)" "-agent-fix.yml"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures setup test(s) failed"
  exit 1
fi
echo "setup tests passed"
