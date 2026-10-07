#!/usr/bin/env bash
# Tests for the scripts claude-review-respond.yml runs: the protected-path
# guard and the per-PR cap count. Needs git and jq; GitHub calls are faked.
#
# Run: bash .github/scripts/test-review-respond.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

expect() { # name, want, got
  if [ "$2" == "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"; echo "  want: $(printf %q "$2")"; echo "  got:  $(printf %q "$3")"
    failures=$((failures + 1))
  fi
}

# --- protected-changes.sh -------------------------------------------------

git init -q -b main "$tmp/repo"
cd "$tmp/repo"
git config user.email t@example.com; git config user.name test
commit() { git add -A; git commit -qm "$1"; git rev-parse HEAD; }

echo a > app.go; mkdir -p .github "docs/team's-config"; echo x > .github/ci.yml
commit base > /dev/null
git checkout -qb pr
echo b >> app.go
before="$(commit 'agent fix')"
check() { "$here/protected-changes.sh" main "$before" HEAD; }

expect "plain code change passes" "" "$(check)"

git checkout -q main; echo y >> .github/ci.yml; commit 'main changes CI' > /dev/null
git checkout -q pr; git merge -q --no-edit main
expect "merging the base branch in passes" "" "$(check)"

echo z > .github/new.yml; commit 'touch CI' > /dev/null
expect "new file under .github/ is caught" ".github/new.yml" "$(check)"
git reset -q --hard HEAD~1

mkdir -p cfg; echo s > cfg/.env.local; commit 'env file' > /dev/null
expect ".env anywhere is caught" "cfg/.env.local" "$(check)"
git reset -q --hard HEAD~1

echo p > "docs/team's-config/a.md"; commit 'extra path' > /dev/null
expect "extra pattern with an apostrophe is caught" "docs/team's-config/a.md" \
  "$(PROTECTED_EXTRA="^(docs/team's-config/)" check)"
expect "extra pattern unset ignores it" "" "$(check)"
git reset -q --hard HEAD~1

# A human already put a protected file on the branch; the agent leaves it alone.
mkdir -p .claude; echo h > .claude/human.md
before="$(commit 'human adds config')"
echo c >> app.go; commit 'agent change' > /dev/null
expect "untouched protected file from a human passes" "" "$(check)"
echo more >> .claude/human.md; commit 'agent edits it' > /dev/null
expect "agent editing that file is caught" ".claude/human.md" "$(check)"

if "$here/protected-changes.sh" main deadbeef HEAD > /dev/null 2>&1; then
  expect "bad commit fails closed" "non-zero exit" "exit 0"
else
  expect "bad commit fails closed" "" ""
fi
cd "$here"

# --- review-responses-today.sh --------------------------------------------

# A fake gh: serves fixture pages for the two endpoints and applies --jq to
# each page with real jq, which is what `gh api --paginate --jq` does.
mkdir -p "$tmp/bin" "$tmp/fx"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
shift # api
url="" expr="."
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) expr="$2"; shift 2 ;;
    -X|-f|-F) shift 2 ;;
    --paginate) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  */workflows/*/runs) pages=("$FIXTURES"/runs-*.json) ;;
  */runs/*/jobs) id="${url%/jobs}"; id="${id##*/}"; pages=("$FIXTURES"/jobs-"$id"-*.json) ;;
  *) echo "unexpected url $url" >&2; exit 1 ;;
esac
for p in "${pages[@]}"; do [ -e "$p" ] && jq -r "$expr" "$p"; done
GH
chmod +x "$tmp/bin/gh"

# Page 1: this run (excluded), a skipped run, a cancelled run, a responder run.
cat > "$tmp/fx/runs-1.json" <<'J'
{"workflow_runs":[
 {"id":100,"conclusion":null},
 {"id":1,"conclusion":"skipped"},
 {"id":2,"conclusion":"cancelled"},
 {"id":3,"conclusion":"success"}]}
J
# Page 2: a gate-only run and a failed responder run.
cat > "$tmp/fx/runs-2.json" <<'J'
{"workflow_runs":[{"id":4,"conclusion":"success"},{"id":5,"conclusion":"failure"}]}
J
cat > "$tmp/fx/jobs-3-1.json" <<'J'
{"jobs":[{"id":31,"name":"Scope and budget","conclusion":"success"},{"id":32,"name":"Claude triages the review","conclusion":"success"}]}
J
cat > "$tmp/fx/jobs-4-1.json" <<'J'
{"jobs":[{"id":41,"name":"Scope and budget","conclusion":"success"},{"id":42,"name":"Claude triages the review","conclusion":"skipped"}]}
J
cat > "$tmp/fx/jobs-5-1.json" <<'J'
{"jobs":[{"id":51,"name":"Scope and budget","conclusion":"success"}]}
J
cat > "$tmp/fx/jobs-5-2.json" <<'J'
{"jobs":[{"id":52,"name":"Claude triages the review","conclusion":"failure"}]}
J

got="$(PATH="$tmp/bin:$PATH" FIXTURES="$tmp/fx" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=100 \
  RESPONDER="Claude triages the review" "$here/review-responses-today.sh" claude/issue-1 2026-01-01)"
expect "cap counts only runs whose responder ran, across pages" "2" "$got"

echo
if [ "$failures" -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
