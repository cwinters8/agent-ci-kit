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
    claude-code-review.yml   Claude reviews each PR push, alongside Codex                (module 2)
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
   - `AGENT_PR_TOKEN` (required): a fine-grained personal access token on your
     own account (GitHub has no repo-owned tokens), limited to this repo only.
     Permissions: Contents and Pull requests read/write; add Issues read/write
     and Actions read-only if you use the daily review sweep. The workflow opens
     agent PRs with it. The built-in `GITHUB_TOKEN` is not a drop-in
     replacement: GitHub blocks Actions from creating PRs unless you turn on
     "Allow GitHub Actions to create and approve pull requests", and even then
     CI on those PRs waits until someone clicks "Approve workflows to run". If
     you accept that manual step, enable the setting and point the "Open draft
     PR" step at `github.token`. If the PR step fails, the workflow comments a
     link on the issue so you can open the PR by hand.
4. Create labels: `agent:fix`, `agent:fix-opus`, `agent:needs-human`, `agent:large-diff`.
5. Protect `main`: require a pull request, but **not** an approving review.
   Agent PRs are opened with your PAT, so GitHub lists you as the author, and
   you cannot approve your own PR. To keep required approvals, put a second
   (bot) account's PAT in `AGENT_PR_TOKEN`, or use your own GitHub App and mint
   its token in the workflow with `actions/create-github-app-token`. App tokens
   expire after an hour, so one pasted into the secret stops working.
6. Open a bug with the "Bug for the agent" template and label it `agent:fix`.

Locally: `make check` runs exactly what CI and the agents run. `make run`
serves the API on `:8080`.

## Adopting it in your project

The fast way: let Claude Code do it. From this checkout, run
`bash setup/install.sh` once, then open Claude Code in your own repo and run
`/adopt-kit`. It reads your code, asks what it cannot work out, fills in the
files below, prepares GitHub, and opens a setup PR for you to review. Run
`/adopt-kit doctor` any time to check a setup.

By hand: copy the kit files, then fill in three files. The workflows themselves stay
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
| `AGENT_MAX_TURNS_CODE_REVIEW` / `AGENT_CODE_REVIEW_MODEL` | 20 / opus | per PR review |
| `AGENT_MAX_DIFF_LINES` | 400 | above this, PR gets `agent:large-diff` |
| `AGENT_INTERACTIVE_MODEL` / `AGENT_SWEEP_MODEL` | sonnet | |

See `docs/COST-CONTROLS.md`.
