#!/usr/bin/env bash
# Prints how many times claude-review-respond.yml actually ran the responder
# job on a branch since a date. A run the gate turned away still concludes
# "success", so run conclusions overcount; jobs are counted instead, across
# every attempt, so rerunning a run cannot reset the count. The current
# attempt is left out: its responder has not run yet.
#
# Usage: review-responses-today.sh <branch> <YYYY-MM-DD>
# Env: GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, RESPONDER (job
# name), GH_TOKEN
set -euo pipefail

branch="$1" since="$2"
runs="$(gh api --paginate -X GET "repos/$GITHUB_REPOSITORY/actions/workflows/claude-review-respond.yml/runs" \
  -f branch="$branch" -f created=">=$since" -F per_page=100 \
  --jq '.workflow_runs[] | select(.conclusion != "skipped") | .id')"
used=0
for id in $runs; do
  n="$(gh api --paginate -X GET "repos/$GITHUB_REPOSITORY/actions/runs/$id/jobs" -f filter=all \
    --jq '.jobs[] | select(.name == $ENV.RESPONDER and .conclusion != "skipped" and .conclusion != null)
      | select((.run_id | tostring) != $ENV.GITHUB_RUN_ID or (.run_attempt | tostring) != $ENV.GITHUB_RUN_ATTEMPT) | .id' | wc -l)"
  used=$((used + n))
done
echo "$used"
