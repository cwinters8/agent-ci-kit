# Autonomous Agent CI Kit

Claude Code agents that fix bugs and open PRs from GitHub Actions, with the cost
controls that keep that from becoming a surprise bill.

Label an issue `agent:fix`. An agent picks it up on a GitHub runner, finds the
bug, makes the smallest fix, runs your checks and opens a draft PR. You review
it, comment `@claude` for changes, and merge. A daily sweep keeps every PR's
review comments moving while you are away.

This repo is a working sample: a small Go todo API with the whole kit wired
around it. Fork it to watch the agents work, then copy the kit files into your
own project.

## What's in the box

```
The kit (copy these into your repo)
  .github/workflows/
    claude-fix-issue.yml     issue -> branch -> draft PR, with routing, caps, guardrails  (modules 1-3)
    claude.yml               @claude follow-ups on PRs: the human review gate            (module 2)
    claude-review-sweep.yml  daily triage of every open review comment                   (module 2)
    pr-checks.yml            the same checks the agent runs, skipped on docs-only PRs    (module 4)
    build-image.yml          source-hash-gated container builds                          (module 4)
  .github/ISSUE_TEMPLATE/agent-fix.yml   a bug report an unattended agent can act on
  .claude/
    skills/                  pr-preflight, review-sweep, code-review, security-review, action-versions
    project-profile.md       your project's facts, read by every skill
    hooks/session-start.sh   installs dependencies in fresh containers
    settings.json
  AGENTS.md / CLAUDE.md      the agent's rulebook
  vps/                       always-on self-hosted runner                                 (module 5)
  docs/COST-CONTROLS.md      every cost control, where it lives, what it bounds
  docs/GUARDRAILS.md         what stops an unattended agent from doing damage

The sample app (replace with yours)
  cmd/server/  internal/  Dockerfile  Makefile  go.mod
```

## Quickstart

1. Fork or "Use this template". Keep it **private** while you try it.
2. Install the Claude GitHub App: https://github.com/apps/claude
3. Add repo secrets:
   - `CLAUDE_CODE_OAUTH_TOKEN` (run `claude setup-token`; uses your Pro/Max plan) **or** `ANTHROPIC_API_KEY` (API billing)
   - `AGENT_PR_TOKEN`: a fine-grained personal access token on your own account
     (GitHub has no repo-owned tokens), limited to this repo only. Permissions:
     Contents and Pull requests read/write; add Issues read/write and Actions
     read-only if you use the daily review sweep. Without it, CI does not run on
     agent PRs.
4. Create labels: `agent:fix`, `agent:fix-opus`, `agent:needs-human`, `agent:large-diff`.
5. Protect `main`: require a pull request, but **not** an approving review.
   Agent PRs are opened with your PAT, so GitHub lists you as the author, and
   you cannot approve your own PR. To keep required approvals, open PRs with a
   GitHub App token or a second account instead.
6. Open a bug with the "Bug for the agent" template and label it `agent:fix`.

Locally: `make check` runs exactly what CI and the agents run. `make run`
serves the API on `:8080`.

## Adopting it in your project

Copy the kit files, then:

- Rewrite `AGENTS.md`'s project sections and every section of
  `.claude/project-profile.md` for your codebase.
- In each `claude*.yml`, replace the "Set up Go" step with your toolchain and
  swap the `make`/`go` entries in `--allowedTools` for your check commands.
- Point `pr-checks.yml` and `build-image.yml` `paths:` at your source files.

## Tuning

Repo variables (Settings → Variables), all optional:

| Variable | Default | |
| --- | --- | --- |
| `AGENT_DAILY_RUN_CAP` | 10 | fix runs per UTC day |
| `AGENT_MAX_TURNS_SONNET` / `_OPUS` | 30 / 40 | per fix run |
| `AGENT_MAX_TURNS_INTERACTIVE` | 20 | per `@claude` run |
| `AGENT_MAX_TURNS_SWEEP` | 60 | per daily sweep |
| `AGENT_MAX_DIFF_LINES` | 400 | above this, PR gets `agent:large-diff` |
| `AGENT_INTERACTIVE_MODEL` / `AGENT_SWEEP_MODEL` | sonnet | |

See `docs/COST-CONTROLS.md`.
