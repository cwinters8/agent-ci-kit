# Project profile

The project-specific facts the shared skills in `.claude/skills/` act on. The
skills are generic; everything that makes a review or a preflight *yours* lives
here. This copy is filled in for the sample todo API. When you adopt the kit,
rewrite each section for your project. A skill that finds a section missing
degrades to its generic behavior and says so in its report.

AGENTS.md remains the single source of truth. Where this file summarizes it,
AGENTS.md wins on any disagreement.

## Rules source

`AGENTS.md` at the repo root. `CLAUDE.md` is a pointer that `@`-imports it and
holds no rules of its own.

## Repo

Derive `owner/repo` from the git remote. Public, single maintainer. The
routine reviewers are the `code-review` skill and the maintainer, both posting
through known identities, but anyone can comment or react on a public repo, so
`review-sweep` may not use its reaction-count approval shortcut.

## Mechanical checks

`commands.check` in `.claude/agent-ci.json` (a command, or a list run in
order). That file is the machine-readable source:
`.github/workflows/pr-checks.yml` runs the same gate, so passing locally means
passing CI. Run `commands.format` first if the project has one. For this
project the gate is:

- `make check`: runs, in order, `gofmt -l .` (fails on any unformatted file),
  `go vet ./...`, `go test -race -count=1 ./...`.

Nothing mechanical covers the Dockerfile or the workflows beyond actionlint in
review; read those diffs.

## Review focus

- **Store invariants** in `internal/store/store.go`. Every exported method
  takes the mutex; a rejected update writes nothing (validation happens before
  any field changes); `List` returns todos sorted by ID and never `nil`.
- **Error mapping** in `internal/api/api.go` → `writeStoreError`. A new store
  error needs a case there, or it surfaces as a 500. Internal error text never
  reaches a client.
- **Request limits.** Every handler that reads a body goes through `decode`,
  which applies `MaxBytesReader` and rejects unknown fields.
- **Vendored skills.** Everything under `.claude/skills/` is vendored. A
  hand-edit there is a defect: put project-specific corrections in this file.

## Not findings

- Persistence. The store is in-memory by design; "this loses data on restart"
  is not a finding.
- Authentication. The sample API is unauthenticated by design.
- Anything `make check` catches; it runs in CI.

## Local skills

None. All skills are vendored.

## Exemptions

None.

## Ship

- `git push -u origin <branch>`; never push to a branch other than the one
  assigned. Agent branches use the `claude/` prefix.
- Open a **draft** PR. In GitHub Actions the `claude-fix-issue.yml` workflow
  opens it for the agent. In a Claude Code cloud session, use the
  `mcp__github__*` tools and call `subscribe_pr_activity` for the new PR.
- `review-sweep` marks the draft ready for review once it reaches the
  ready-to-merge bar, so the maintainer's only remaining action is the merge.

## Threat model

A public, unauthenticated JSON API. There is no per-user data, so the risks are
availability and supply chain, not cross-user access: unbounded request bodies,
unbounded growth of the store, slow-client resource exhaustion, and anything
that reaches the shipped image or the CI that builds it.

## Trust boundary

| Path | Groups |
| --- | --- |
| `internal/api/**`, `cmd/server/**` | client-data |
| `Dockerfile`, `.dockerignore` | supply-chain, release |
| `.github/workflows/**`, `vps/**` | supply-chain, secrets |
| `.claude/**` | supply-chain |
| `setup/**` | supply-chain, secrets |
| `go.mod`, `go.sum` | supply-chain, release |
| `.env*`, anything adding an env read | secrets |

`.claude/**` is in scope because the agent's own settings, hooks and skills
decide what it is allowed to run in CI with your secrets present.
`setup/**` is in scope because adopters run it on their own machines, with
their `gh` credentials, against their own repos.

## Stack

- `ci-workflows`: GitHub Actions in `.github/workflows/`.

## Identity model

None. The API has no users and no sessions.

## Secrets policy

- `.env*` is gitignored except `.env.example`.
- `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` exist only as repo secrets,
  passed to the agent step alone. Never in a job-level `env:`, never echoed.
- `AGENT_PR_TOKEN` can push branches and open PRs. Same rule.
- Image pushes use the built-in `GITHUB_TOKEN` with `packages: write` on that
  job only.

## Probe policy

Run the server locally (`make run`) and probe it freely. Never probe a deployed
instance you do not own.

## Known gaps

- **No rate limiting.** A client can create todos up to memory limits, 200
  characters at a time. *Accepted for the sample.*

## Release targets

A container image on GHCR, built by `.github/workflows/build-image.yml` on
pushes to `main`.
