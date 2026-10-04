# Agent guide

Shared instructions for AI coding agents (Claude Code, Codex, etc.) working in
this repository. Humans should read it too: it records the project's current
stage and conventions.

This file is the single source of truth for project facts.
`.claude/project-profile.md` and the skills cite it; where either disagrees,
this file wins. It is filled in for the sample todo API; when you adopt the
kit, keep the agent sections and rewrite the project ones.

## Project status

A sample project. It exists so the agent CI around it has something real to
work on. When you adopt the kit, replace this section with your project's
stage.

**Pre-launch projects:** state it plainly and name one machine-readable flag
that is the source of truth for it. While it says "not launched":

- Do not add migration or backward-compatibility code for state or formats no
  real user has.
- Do not flag "this would break existing users" as a review concern. Reviewers
  (human or bot) raising it get declined with a pointer to this section.
- **This never covers security.** "No users yet" makes a security fix cheap, not
  optional.

Why this section exists: without it, review bots raise backward-compatibility
concerns on every PR, agents add shims to satisfy them, and you pay tokens for
both sides of an argument about users you do not have.

## What this project is

A JSON todo API in Go, standard library only. Todos live in memory; restarting
the server empties it. Routes use Go 1.22+ `net/http` method patterns.

## Layout

- `cmd/server/main.go`: entry point. Reads `PORT` (default 8080), sets server
  timeouts, shuts down gracefully on SIGINT/SIGTERM.
- `internal/store/`: the in-memory store. All validation of todo fields lives
  here, so every caller gets the same rules.
- `internal/api/`: HTTP handlers, JSON encoding, request limits, error mapping,
  request logging.
- `Dockerfile`: static binary on distroless, non-root.
- `Makefile`: `make check` is the one command CI and agents both run.
- `.claude/agent-ci.json`: the toolchain, the project's commands named by
  purpose (install, format, lint, test, build, check), extra agent permissions
  and protected paths the workflows read. Schema alongside;
  reference in `docs/PROJECT-CONFIG.md`.
- `.claude/project-profile.md`: the project facts the vendored skills read.
- `setup/`: the `adopt-kit` skill buyers install to set the kit up in their
  own repo, and its `doctor.sh` checker. Authored here, not vendored.
- `.claude/skills/`: vendored skills. Never hand-edit; see
  [Shared skills](#shared-skills).
- `.github/workflows/claude-*.yml`: the agent workflows. See [Agents in CI](#agents-in-ci).
- `.github/actions/project-setup/`: sets up the toolchain from
  `.claude/agent-ci.json`; every workflow that runs checks uses it.

## API

| Method | Path | Success | Errors |
| --- | --- | --- | --- |
| GET | `/healthz` | 200 `{"status":"ok"}` | |
| GET | `/todos?done=true\|false` | 200 array (never `null`) | 400 bad filter |
| POST | `/todos` `{"title"}` | 201 + `Location` | 400 bad JSON, 422 blank/long title |
| GET | `/todos/{id}` | 200 | 400 bad id, 404 |
| PATCH | `/todos/{id}` `{"title"?, "done"?}` | 200 | 400, 404, 422 |
| DELETE | `/todos/{id}` | 204 | 400, 404 |

Every error body is `{"error": "..."}` with `Content-Type: application/json`.

## Commands

- `make check`: gofmt check, `go vet`, `go test -race`. Run before every commit.
  It is `commands.check` in `.claude/agent-ci.json`, which also names the
  `format`, `lint`, `test` and `build` commands.
- `make run`: start the server on `:8080`.
- `make image`: build the container (needs Docker).

## Agents in CI

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `claude-fix-issue.yml` | label `agent:fix` (Sonnet) or `agent:fix-opus` | issue → `claude/` branch → draft PR, behind a daily run cap and protected-path guardrails |
| `claude.yml` | `@claude` in a comment or review | follow-up edits on the same branch; the human-in-the-loop review gate |
| `claude-review-sweep.yml` | daily schedule, or manual | triage every open review comment to fixed or declined; flag PRs ready to merge |
| `pr-checks.yml` | PRs touching Go code | `commands.check` from `.claude/agent-ci.json` |
| `build-image.yml` | pushes to `main` touching Go code | source-hash gate over `image.inputs`: reuse a matching image, build only when inputs changed |

Agents never push to the default branch and never merge. Merging is the
maintainer's decision, always.

## QA and code review

The maintainer is the merge decision, not the review bottleneck. Agents own QA
end to end through the skills in `.claude/skills/`:

1. **Before pushing:** `pr-preflight`. Mechanical checks, self code-review,
   project-specific and security checks, then push and open a draft PR.
2. **After review feedback lands:** `review-sweep`. Every unhandled comment ends
   fixed or declined with a reason. The daily sweep workflow runs it across all
   open PRs, so nothing depends on a session still being alive.

Targeted skills for recurring failure modes:

- `code-review`: reviews the local diff (default) or a PR number. Scores each
  finding and drops what it cannot stand behind, so a clean report is normal.
- `action-versions`: on any workflow change, looks up the current major of
  every `uses:` action instead of trusting a remembered tag.
- `security-review`: when a diff crosses the trust boundary in
  `.claude/project-profile.md`, and as a full sweep before any release.

Triage state lives in emoji reactions on each review comment: 👀 seen, 🚀 fix
pushed, 👎 declined (with a reply saying why). A bare 👎 from the maintainer
means "rejected, do not argue". When a PR has every comment in a terminal state,
green CI and an approving verdict, the sweep posts one "ready to merge" comment.

## Session behavior

**Never schedule self check-ins, wake-ups or polling loops.** Webhooks deliver
review comments and CI failures; the daily sweep catches what webhooks drop.
A per-PR poll adds nothing and costs a full agent session every time it fires,
multiplied by every open PR. If a run truly needs to wait on something no event
covers, ask first.

## Shared skills

`.claude/skills/` is vendored, not authored here. A hand-edit to a vendored
`SKILL.md` is a defect: the next sync overwrites it and the fix never reaches
your other projects. Project-specific corrections go in
`.claude/project-profile.md`; improvements to a skill go upstream, then re-sync.

Skills rather than marketplace plugins, deliberately: skills are read from the
repo and are live on a session's first turn, in CI and in cloud sessions alike.
Plugins have to install first, and some need interactive OAuth a headless run
cannot complete.

## Conventions

- Keep secrets out of the repo. `.env*` is gitignored except `.env.example`.
- Agent credentials (`ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`) live only
  in repo secrets and are scoped to the step that needs them.
- Agent branches use the `claude/` prefix. Agents never push elsewhere.
- Agents do not edit `.github/` or `.claude/`. The fix workflow refuses
  to open a PR that does; a human makes those changes.
- Standard library only unless a dependency clearly earns its place.
- New behavior ships with a test in the same change.
