---
name: adopt-kit
description: Set up the Autonomous Agent CI Kit in the current repo. Reads the codebase, asks only what it cannot infer, fills in the kit's config, AGENTS.md and project profile, prepares GitHub, opens a setup PR, then walks through the first agent fix. Use when asked to "adopt the kit", "set up agent CI", "install the agent workflows", or with `/adopt-kit doctor` to check an existing setup.
---

# Adopt the agent CI kit

You are setting up the kit's agent workflows in the user's own repository. The
user bought the kit; this is their first hands-on experience of it, so do the
work and keep questions few. The finished state:

1. A setup PR on their repo with the kit files, filled in for their project.
2. `doctor.sh` reporting no ✗.
3. The user knows exactly which steps are theirs (secrets, GitHub App) and has
   done them.
4. After they merge, one real issue fixed by the agent as proof.

## Ground rules

- **The kit lives at the path in `kit-path`**, in this skill's base directory.
  Call it `$KIT`. Never edit anything under `$KIT`.
- **The kit is the source of truth, not this file.** Before writing the
  config, read `$KIT/docs/PROJECT-CONFIG.md` and
  `$KIT/.claude/agent-ci.schema.json`. Before the GitHub steps, read
  `$KIT/README.md`. If they disagree with this skill, they win.
- **Never ask for a secret in the conversation.** Not a token, not an API key,
  not "paste it here and I'll set it". The user sets secrets themselves with
  `gh secret set` in their own terminal.
- **Ask before anything leaves the machine.** Labels, variables, rulesets,
  issues, pushes: show the exact commands, batched, and get one yes.
- **Never commit to the default branch.** Work on `agent-ci-kit-setup`.
- **Never overwrite a file the user already has.** Merge into it (rules in
  step 4) and say what you merged.
- **Ask only what the repo cannot answer.** Use the AskUserQuestion tool when
  available, several questions per call.

## Doctor mode

If the argument is `doctor`, or the repo already has `.claude/agent-ci.json`:
run `bash <this skill's base directory>/doctor.sh`, explain each ✗ and ! in a
sentence, and offer to fix the ones that are local files. For an existing
setup, fix what doctor flags and skip to step 5 for anything on GitHub.

## 1. Preflight

Stop and say why if any of these fail:

- Inside a git repo whose `origin` is on github.com.
- Working tree clean (`git status --porcelain` empty). Unrelated changes must
  not end up in the setup PR.
- `gh auth status` succeeds, and `jq` is installed.
- `$KIT/.claude/agent-ci.schema.json` exists. If not, the kit checkout is
  older than this skill: tell them to `git pull` in `$KIT` and re-run
  `bash setup/install.sh`.

Then `git switch -c agent-ci-kit-setup`.

## 2. Survey the repo

No questions yet. Work out, and note the file that told you each answer:

- **Runtime and toolchain.** The kit sets up `go`, `node` and `python`. Find
  the version file each needs (`go.mod`; `.nvmrc`, `.node-version` or
  `package.json`; `.python-version` or `pyproject.toml`) and the package
  manager from the lockfile. Anything else (Rust, Ruby, Java, ...) gets
  `"toolchain": {}`, which only works if GitHub's `ubuntu-latest` image already
  has that runtime. Say so plainly; if it does not, stop and tell the user the
  kit cannot set up their runtime yet.
- **Commands, by purpose** (`install`, `format`, `lint`, `typecheck`, `test`,
  `build`, `check`). The best evidence is the repo's existing CI: what it runs
  today is what works. Then Makefile targets, `package.json` scripts,
  `pyproject.toml`, `justfile`, `tox.ini`, `noxfile.py`. `check` is the gate
  CI and agents both run; prefer one entry point (`make check`, `pnpm check`)
  over a list.
- **Dependency files**: manifests and lockfiles.
- **Protected paths**: things an unattended agent should never change. Look
  for database migrations, generated code, vendored code, infrastructure
  (`terraform/`, `infra/`, `k8s/`), and release config.
- **Container image**: a Dockerfile, what it copies in (that becomes
  `image.inputs`), and whether anything pushes it today.
- **Existing agent files**: `AGENTS.md`, `CLAUDE.md`, `.claude/`, and any
  workflow with the same name as a kit workflow.
- **Trust boundary** for the profile: where auth, data access, secrets, user
  input, CI and dependencies live.
- **Project basics** for AGENTS.md: what it is, layout, how to run it.

Then prove the commands. Run `install` and every named command locally. A
command that fails here fails in CI, so fix it or raise it. Each non-install
command must be one plain command (the schema's `$defs.command.pattern`: no
quotes, `&&`, pipes or `$`). If the gate is a chain, add a Makefile target or
package script that runs it, and say you did: that change goes in the setup PR.

## 3. Interview

Open with a short summary of what you found (stack, commands, protected
paths, image) so the user can correct it. Then ask only what is still open.
Usually that is:

- **Billing**: Claude subscription (`CLAUDE_CODE_OAUTH_TOKEN`) or API key
  (`ANTHROPIC_API_KEY`). One line on the tradeoff from
  `$KIT/docs/COST-CONTROLS.md`.
- **Which pieces**: issue-to-PR fixes (`claude-fix-issue.yml`, the core),
  `@claude` follow-ups on PRs (`claude.yml`), the daily review sweep
  (`claude-review-sweep.yml`), PR checks (`pr-checks.yml`), image builds
  (`build-image.yml`; only with a Dockerfile). Recommend the first three. Add
  PR checks unless their CI already runs the same gate on every PR; running
  it twice only costs minutes. The VPS runner (`vps/`) is a separate guide module; leave it out.
- **Budget**: the defaults (10 fix runs a day, Sonnet unless labeled
  `agent:fix-opus`) suit most solo projects. Ask whether they want different
  caps; only non-default answers become repo variables.
- **Protected paths**: confirm your list.
- **Visibility**: if the repo is public, walk them through "Before enabling
  on a public repo" in `$KIT/docs/GUARDRAILS.md` and apply what they choose.
- **Project status**: launched, or pre-launch? It goes in AGENTS.md and stops
  reviewers asking for backward compatibility nobody needs.

## 4. Write the files

Copy from `$KIT`, keeping paths:

- `.github/workflows/`: the workflows they chose
- `.github/actions/project-setup/`
- `.github/ISSUE_TEMPLATE/agent-fix.yml`
- `.claude/skills/` and `.claude/skills.json` (vendored; copy as is)
- `.claude/hooks/session-start.sh`, `.claude/settings.json`
- `.claude/agent-ci.schema.json`
- `.claude/agent-ci.json`, `.claude/project-profile.md`, `AGENTS.md`,
  `CLAUDE.md`: as starting points, rewritten below
- `docs/PROJECT-CONFIG.md`, `docs/COST-CONTROLS.md`, `docs/GUARDRAILS.md`.
  If they already have a `docs/` with a different purpose, use
  `docs/agent-ci/` and fix the links that point at these files.

Never copy the sample app (`cmd/`, `internal/`, `go.mod`, the kit's
`Dockerfile` and `Makefile`), `README.md`, `INVENTORY.md`, `setup/` or `vps/`.

Merge rules for files that already exist:

- `CLAUDE.md`: keep it; add an `@AGENTS.md` line if missing.
- `AGENTS.md`: keep their content; append the kit's agent sections.
- `.claude/settings.json`: merge the kit's `SessionStart` hook into their
  hooks; keep everything else.
- A workflow with the same file name: stop and ask. Do not rename or merge
  CI files on your own.

Fill in:

- **`.claude/agent-ci.json`** from the survey, field by field against the
  schema. Every command you name is on the agents' allowlist, so name only
  what an agent should be able to run. `jq empty` must pass.
- **`.claude/project-profile.md`**: keep every section heading of the kit's
  copy, in order, and rewrite each body for their project. A section with
  nothing to say gets "None." rather than being deleted; the skills read
  these by heading.
- **`AGENTS.md`**: replace the project sections (Project status, What this
  project is, Layout, the sample's API table, Commands) with theirs. Keep the
  agent sections (Agents in CI, QA and code review, Session behavior, Shared
  skills, Conventions), dropping table rows for workflows they skipped and
  convention lines that are about the sample ("Standard library only").
- **`paths:` filters** in `pr-checks.yml` and `build-image.yml`: their source
  globs, manifests, `.claude/agent-ci.json`, the setup action and the
  workflow file itself. GitHub reads these before a runner starts, so they
  cannot come from the config. Keep `build-image.yml`'s list a superset of
  `image.inputs`. Leave the rest of the workflow YAML alone.

Run `doctor.sh`. Fix every ✗ above the GitHub section before going on.

## 5. GitHub

**Your part**, after one yes for the batch (read `$KIT/README.md` for anything
that changed since this skill was written):

- Labels, with `--force` so a re-run is harmless:
  ```
  gh label create agent:fix         --color 1d76db --description "Agent fixes this issue (Sonnet)" --force
  gh label create agent:fix-opus    --color 5319e7 --description "Agent fixes this issue (Opus)" --force
  gh label create agent:needs-human --color d93f0b --description "Agent stopped; a human must act" --force
  gh label create agent:large-diff  --color fbca04 --description "Agent diff over AGENT_MAX_DIFF_LINES" --force
  ```
- Repo variables, only for caps they changed: `gh variable set NAME --body VALUE`.
- Require a PR on the default branch, if it does not already (doctor says):
  ```
  gh api repos/OWNER/REPO/rulesets -X POST --input - <<'EOF'
  {"name": "Require PR", "target": "branch", "enforcement": "active",
   "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
   "rules": [{"type": "pull_request", "parameters": {
     "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false,
     "require_code_owner_review": false, "require_last_push_approval": false,
     "required_review_thread_resolution": false}}]}
  EOF
  ```
  Zero required approvals is deliberate for a solo maintainer, who cannot
  approve their own PR. With collaborators, suggest 1.
  On a free personal account, private repos cannot use rulesets or branch
  protection and this call fails with 403. Say so, and that the other
  guardrails still hold: agents push only `claude/` branches and the
  workflow opens drafts.

**Their part.** You cannot do these and must not try. Give them as a numbered
list, to run in a separate terminal:

1. Install the Claude GitHub App on this repo: https://github.com/apps/claude
2. The Claude credential they chose:
   - subscription: `claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN` and paste at the prompt
   - API: `gh secret set ANTHROPIC_API_KEY` and paste at the prompt
3. `AGENT_PR_TOKEN`: a fine-grained personal access token for this repo only,
   with the permissions `$KIT/README.md` lists, created at
   https://github.com/settings/personal-access-tokens/new. Then
   `gh secret set AGENT_PR_TOKEN`. Without it, CI never runs on agent PRs.

When they say done, re-run doctor and confirm the secret lines turned ✓.

## 6. Open the setup PR

Commit everything on `agent-ci-kit-setup` with a message that lists what was
added, push, and `gh pr create`. The PR body says:

- what you detected and from where,
- the allowlist and protected paths, called out for review, since they are
  exactly what an unattended agent may run and touch,
- any Makefile target or script you added,
- what is left (their part of step 5, if not done yet).

Tell the user two things: their own `pr-checks` run on this PR is the first
proof the config works, and the agent workflows read the config from the
default branch, so nothing agent-side runs until they merge.

## 7. First agent fix

After they merge, run doctor again. Then propose one smoke-test issue: a real,
small problem you saw during the survey (a missing test for an existing
function, a clear TODO, a small bug). Not a made-up one. Write it in the
shape of `.github/ISSUE_TEMPLATE/agent-fix.yml` (what happens, what should
happen, steps, where to look, done when), show it, and on a yes create it with
`gh issue create`. Labeling it `agent:fix` starts a paid run, so the user
applies the label, or says yes to you applying it.

Then tell them what to watch: the run in the Actions tab, the draft PR it
opens, `pr-checks` on that PR, and `@claude` in a PR comment to ask for a
change.

## Report

End with a few lines: the setup PR link, doctor's result, and anything still
open. Nothing else.
