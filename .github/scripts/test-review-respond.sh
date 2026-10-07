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

printf x > $'.github/evil\n.yml'; commit 'newline in a name' > /dev/null
expect "name with a newline under .github/ is caught" "$(printf %q $'.github/evil\n.yml')" "$(check)"
git reset -q --hard HEAD~1

echo p > "docs/team's-config/a.md"; commit 'extra path' > /dev/null
expect "extra pattern with an apostrophe is caught" "docs/team's-config/a.md" \
  "$(PROTECTED_EXTRA="^(docs/team's-config/)" check)"
expect "extra pattern unset ignores it" "" "$(check)"
git reset -q --hard HEAD~1

# A human already put protected files on the branch; the agent leaves them
# alone. One name is also a glob that matches the other.
mkdir -p .claude; echo h > .claude/human.md; echo g > '.claude/h*.md'
before="$(commit 'human adds config')"
echo c >> app.go; commit 'agent change' > /dev/null
expect "untouched protected file from a human passes" "" "$(check)"
echo more >> .claude/human.md; commit 'agent edits it' > /dev/null
expect "agent editing that file is caught" ".claude/human.md" "$(check)"
git reset -q --hard HEAD~1
git rm -q .claude/human.md; commit 'agent reverts it to base' > /dev/null
expect "agent reverting that file to the base is caught" ".claude/human.md" "$(check)"

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

T='"updated_at":"2026-01-01T09:00:00Z"'
Y='"updated_at":"2025-12-31T09:00:00Z"'
# Page 1: this run (now on attempt 2), a skipped run, a cancelled run that
# got as far as the responder, and a normal responder run.
cat > "$tmp/fx/runs-1.json" <<J
{"workflow_runs":[
 {"id":100,"conclusion":null,$T},
 {"id":1,"conclusion":"skipped",$T},
 {"id":2,"conclusion":"cancelled",$T},
 {"id":3,"conclusion":"success",$T}]}
J
# Page 2: a gate-only run, a failed responder run, a run from yesterday
# rerun today, and a run last touched yesterday.
cat > "$tmp/fx/runs-2.json" <<J
{"workflow_runs":[{"id":4,"conclusion":"success",$T},{"id":5,"conclusion":"failure",$T},
 {"id":6,"conclusion":"success",$T},{"id":7,"conclusion":"success",$Y}]}
J
R='"name":"Claude triages the review","started_at":"2026-01-01T10:00:00Z"'
RY='"name":"Claude triages the review","started_at":"2025-12-31T10:00:00Z"'
G='"name":"Scope and budget","started_at":"2026-01-01T10:00:00Z"'
# Attempt 1 of this run responded; attempt 2 (now) has not yet.
cat > "$tmp/fx/jobs-100-1.json" <<J
{"jobs":[{"id":1001,"run_id":100,"run_attempt":1,$R,"conclusion":"success"},
 {"id":1002,"run_id":100,"run_attempt":2,$G,"conclusion":"success"},
 {"id":1003,"run_id":100,"run_attempt":2,$R,"conclusion":null}]}
J
cat > "$tmp/fx/jobs-1-1.json" <<J
{"jobs":[{"id":11,"run_id":1,"run_attempt":1,$R,"conclusion":"success"}]}
J
cat > "$tmp/fx/jobs-2-1.json" <<J
{"jobs":[{"id":21,"run_id":2,"run_attempt":1,$R,"conclusion":"cancelled"}]}
J
cat > "$tmp/fx/jobs-3-1.json" <<J
{"jobs":[{"id":31,"run_id":3,"run_attempt":1,$G,"conclusion":"success"},{"id":32,"run_id":3,"run_attempt":1,$R,"conclusion":"success"}]}
J
cat > "$tmp/fx/jobs-4-1.json" <<J
{"jobs":[{"id":41,"run_id":4,"run_attempt":1,$G,"conclusion":"success"},{"id":42,"run_id":4,"run_attempt":1,$R,"conclusion":"skipped"}]}
J
cat > "$tmp/fx/jobs-5-1.json" <<J
{"jobs":[{"id":51,"run_id":5,"run_attempt":1,$G,"conclusion":"success"}]}
J
cat > "$tmp/fx/jobs-5-2.json" <<J
{"jobs":[{"id":52,"run_id":5,"run_attempt":1,$R,"conclusion":"failure"}]}
J
# Yesterday's attempt does not count toward today; today's rerun does.
cat > "$tmp/fx/jobs-6-1.json" <<J
{"jobs":[{"id":61,"run_id":6,"run_attempt":1,$RY,"conclusion":"success"},
 {"id":62,"run_id":6,"run_attempt":2,$R,"conclusion":"success"}]}
J
# Never fetched (last updated yesterday); counted if it were.
cat > "$tmp/fx/jobs-7-1.json" <<J
{"jobs":[{"id":71,"run_id":7,"run_attempt":1,$R,"conclusion":"success"}]}
J

got="$(PATH="$tmp/bin:$PATH" FIXTURES="$tmp/fx" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=100 GITHUB_RUN_ATTEMPT=2 \
  RESPONDER="Claude triages the review" "$here/review-responses-today.sh" claude/issue-1 2026-01-01)"
# Counted: run 100 attempt 1, run 2, run 3, run 5, run 6 attempt 2. Not:
# skipped run 1 and stale run 7 (never fetched), run 4 (gate only), run 6
# attempt 1 (yesterday), run 100 attempt 2 (this one).
expect "cap counts today's responder jobs across pages, attempts, reruns and cancellations" "5" "$got"

echo
if [ "$failures" -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
