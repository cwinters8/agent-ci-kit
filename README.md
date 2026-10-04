# Autonomous Agent CI Kit

Claude Code agents that fix bugs and open PRs from GitHub Actions, with the cost
controls that keep that from becoming a surprise bill.

Label an issue `agent:fix`. An agent picks it up on a GitHub runner, finds the
bug, makes the smallest fix, runs your checks and opens a draft PR. You review
it, comment `@claude` for changes, and merge. Review comments on agent PRs get
fixed or answered as soon as they land, and a daily sweep catches the rest.

This repo is a working sample: a small Go todo API with the whole kit wired
around it. Fork it to watch the agents work, then copy the kit files into your
own project.

## What's in the box

```
The kit (copy these into your repo)
  .github/workflows/
    claude-fix-issue.yml     issue -> branch -> draft PR, with routing, caps, guardrails  (modules 1-3)
    claude.yml               @claude follow-ups on PRs: the human review gate            (module 2)
    claude-review-respond.yml answers each review on an agent PR as it lands            (module 2)
    claude-review-sweep.yml  daily triage of every open review comment                   (module 2)
    pr-checks.yml            the same checks the agent runs, skipped on docs-only PRs    (module 4)
    build-image.yml          source-hash-gated container builds                          (module 4)
  .github/ISSUE_TEMPLATE/agent-fix.yml   a bug report an unattended agent can act on
  .github/actions/project-setup/   toolchain + install from agent-ci.json, shared by every workflow
  .claude/
    agent-ci.json            your toolchain and commands, read by every workflow
    skills/                  pr-preflight, review-sweep, code-review, security-review, action-versions
    project-profile.md       your project's facts, read by every skill
    hooks/session-start.sh   installs dependencies in fresh containers
    settings.json
  AGENTS.md / CLAUDE.md      the agent's rulebook
  vps/                       always-on self-hosted runner                                 (module 5)
  docs/COST-CONTROLS.md      every cost control, where it lives, what it bounds
  docs/GUARDRAILS.md         what stops an unattended agent from doing damage
  docs/PROJECT-CONFIG.md     every field of agent-ci.json, with Node and Python examples

The sample app (replace with yours)
  cmd/server/  internal/  Dockerfile  Makefile  go.mod
```

## Quickstart

1. Fork or "Use this template". Keep it **private** while you try it.
2. Install the Claude GitHub App: https://github.com/apps/claude
3. Add repo secrets:
   - `CLAUDE_CODE_OAUTH_TOKEN` (run `claude setup-token`; uses your Pro/Max plan) **or** `ANTHROPIC_API_KEY` (API billing)
   - `AGENT_PR_TOKEN`: fine-grained PAT, this repo only, Contents + Pull requests read/write. Without it, CI does not run on agent PRs.
4. Create labels: `agent:fix`, `agent:fix-opus`, `agent:needs-human`, `agent:large-diff`.
5. Protect `main` (require a PR).
6. Open a bug with the "Bug for the agent" template and label it `agent:fix`.

Locally: `make check` runs exactly what CI and the agents run. `make run`
serves the API on `:8080`.

## Adopting it in your project

Copy the kit files, then fill in three files. The workflows themselves stay
as they are.

1. `.claude/agent-ci.json`: your toolchain, install command, checks, the
   extra commands agents may run, and paths they must never touch. Every
   workflow and the session hook read it. Field reference and examples in
   `docs/PROJECT-CONFIG.md`.
2. `.claude/project-profile.md`: the prose facts the skills need (review
   focus, threat model, trust boundary).
3. `AGENTS.md`: the project sections.

Then point the `paths:` filters in `pr-checks.yml` and `build-image.yml` at
your source files. GitHub reads those before a runner starts, so they are the
one thing the config cannot set. No container image? Delete `build-image.yml`
and leave `image` out of the config.

## Tuning

Repo variables (Settings → Variables), all optional:

| Variable | Default | |
| --- | --- | --- |
| `AGENT_DAILY_RUN_CAP` | 10 | fix runs per UTC day |
| `AGENT_MAX_TURNS_SONNET` / `_OPUS` | 30 / 40 | per fix run |
| `AGENT_MAX_TURNS_INTERACTIVE` | 20 | per `@claude` run |
| `AGENT_MAX_TURNS_SWEEP` | 60 | per daily sweep |
| `AGENT_MAX_TURNS_REVIEW` | 30 | per review response |
| `AGENT_REVIEW_DAILY_CAP` | 5 | review responses per PR per UTC day |
| `AGENT_REVIEW_BRANCH_PREFIX` | `claude/issue-` | PRs that get review responses without `@claude` |
| `AGENT_REVIEW_BOTS` | `chatgpt-codex-connector[bot]` | review bots that trigger a response; comma-separated, no spaces, with the `[bot]` suffix |
| `AGENT_MAX_DIFF_LINES` | 400 | above this, PR gets `agent:large-diff` |
| `AGENT_INTERACTIVE_MODEL` / `AGENT_SWEEP_MODEL` | sonnet | `AGENT_SWEEP_MODEL` also runs review responses |

See `docs/COST-CONTROLS.md`.
