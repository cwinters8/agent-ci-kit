#!/usr/bin/env bash
# Prints how many claude-review-respond.yml runs on a branch since a date
# actually ran the responder job. A run the gate turned away still concludes
# "success", so the run conclusion alone overcounts.
#
# Usage: review-responses-today.sh <branch> <YYYY-MM-DD>
# Env: GITHUB_REPOSITORY, GITHUB_RUN_ID (excluded), RESPONDER (job name), GH_TOKEN
set -euo pipefail

branch="$1" since="$2"
runs="$(gh api --paginate -X GET "repos/$GITHUB_REPOSITORY/actions/workflows/claude-review-respond.yml/runs" \
  -f branch="$branch" -f created=">=$since" -F per_page=100 \
  --jq '.workflow_runs[] | select(.id != ($ENV.GITHUB_RUN_ID | tonumber) and .conclusion != "skipped" and .conclusion != "cancelled") | .id')"
used=0
for id in $runs; do
  n="$(gh api --paginate "repos/$GITHUB_REPOSITORY/actions/runs/$id/jobs" \
    --jq '.jobs[] | select(.name == $ENV.RESPONDER and .conclusion != "skipped") | .id' | wc -l)"
  used=$((used + n))
done
echo "$used"
