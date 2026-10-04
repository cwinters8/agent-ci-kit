# Cost controls

Every control in this kit, where it lives, and what it bounds. Module 3 of the
guide explains the reasoning; this page is the reference.

| Control | Where | Bounds | Default |
| --- | --- | --- | --- |
| Model routing | `claude-fix-issue.yml` → `Route model` | price per token | Sonnet; Opus only via `agent:fix-opus` |
| Turn cap | `--max-turns` in each workflow | one run's length | 30 Sonnet / 40 Opus / 20 interactive / 30 review response / 60 sweep |
| Wall-clock cap | `timeout-minutes` | a stuck run | 30 fix / 20 interactive / 20 review response / 45 sweep |
| Daily run cap | `claude-fix-issue.yml` → `Check daily run cap` | a bad day | 10 runs per UTC day |
| Per-PR review cap | `claude-review-respond.yml` → `Check per-PR daily cap` | a reviewer and the agent trading rounds | 5 responses per PR per UTC day; the daily sweep takes over after |
| Human trigger | label / `@claude`, write access required | who can spend | maintainers only; review responses also start for allowlisted review bots, on agent PRs only |
| Batched review | `claude-review-respond.yml`, `claude-review-sweep.yml` | review-comment bursts | one run per submitted review, not per comment; a burst on one PR collapses to one queued run. Daily sweep: one session per day |
| No polling | AGENTS.md → Session behavior | idle sessions | never |
| Path filters | `pr-checks.yml`, `build-image.yml` `paths:` | CI on docs/config-only PRs | Go code only |
| Source-hash gate | `build-image.yml` | image builds | build only when shipped inputs change; tests and comments-in-tests never rebuild |
| Layer cache | `build-image.yml` `cache-from: type=gha` | rebuild time | module download layer reused |
| Cost report | `Report cost` step → job summary | visibility | every fix run and review response |

All caps are repo variables, so you tune them in Settings → Variables without
editing YAML.

## Why Sonnet by default

Most agent-fixable bugs are small and well-specified. Sonnet handles them at a
fraction of Opus's per-token price. Opus is worth it for a bug that needs real
reasoning across files, and you know which issues those are when you label them.
Routing by label keeps that decision with you instead of with a heuristic.

The `Report cost` step prints each run's turns and dollar cost in the job
summary. Compare a few Sonnet and Opus runs on your own issues before changing
the default.

## Subscription vs API billing

| | `CLAUDE_CODE_OAUTH_TOKEN` (Pro/Max) | `ANTHROPIC_API_KEY` |
| --- | --- | --- |
| Billing | flat monthly | per token |
| Limit | your plan's usage limits, shared with your own interactive Claude Code use | spend limits you set in the Console |
| Failure mode | agent runs stall when you hit the limit | spend grows with usage |
| Best for | solo dev, steady low volume | teams, bursty volume, hard per-month budget |

Set exactly one as a repo secret. The workflows pass both inputs; the empty one
is ignored.
