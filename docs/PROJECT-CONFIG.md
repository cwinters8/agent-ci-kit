# Project config

`.claude/agent-ci.json` is where your project's toolchain and commands live.
The workflows, the session hook and the fix agent's prompt all read it, so
adopting the kit means filling in this file, not editing YAML. Your editor
validates it against `.claude/agent-ci.schema.json`.

The copy in this repo is filled in for the Go sample.

## Fields

| Field | Required | Read by | What it does |
| --- | --- | --- | --- |
| `toolchain` | yes | `project-setup` action | Runtimes to install: any of `go`, `node`, `python`, each with a `version_file`. `node` also takes `package_manager` (`npm`, `pnpm`, `yarn`; the last two are enabled through corepack). `{}` if the runner image already has what you need. |
| `commands` | yes | everything below | Your commands, named by purpose. See [Commands](#commands). |
| `allow` | no | agent workflows | Extra permission patterns for agents beyond the named commands and git, e.g. `go test:*` to run one package. A trailing `:*` allows any arguments. Anything not named or listed is denied in a headless run. |
| `dependency_files` | no | fix agent prompt | Manifests and lockfiles. The fix agent changes them only when the bug is in a dependency. |
| `protected_paths` | no | fix workflow guardrail | Path prefixes an unattended agent may never change. The fix workflow refuses to open a PR that touches one. `.github/`, `.claude/` and `.env*` are always protected and cannot be removed. |
| `image` | no | `build-image.yml` | `inputs`: git pathspecs for everything that ends up in the image (`:!:` excludes); their content hash decides whether to build. `context` and `dockerfile` default to `.` and `Dockerfile`. Leave `image` out and delete the workflow if you ship no image. |

## Commands

Each command has a name that says what it is for, so a workflow or an agent
picks the one it needs instead of guessing from a list. Only `check` is
required.

| Name | Who runs it | When |
| --- | --- | --- |
| `install` | `project-setup` action, `session-start.sh` | Once, after the toolchain, before the agent starts. Never granted to agents. |
| `format` | agents | Before `check`, so formatting never fails the gate. |
| `lint` | agents | To check one concern without the full gate. |
| `typecheck` | agents | Same. |
| `test` | agents | While iterating on a fix. |
| `build` | agents | To confirm the project still compiles or bundles. |
| `check` | `pr-checks.yml`, agents | The gate: CI runs it on every PR, agents must pass it before pushing. One command or a list run in order. Prefer one entry point (`make check`, `pnpm check`) so CI and agents can never drift. |

Every named command except `install` is also on the agents' allowlist, so you
never list a command twice.

Commands are single commands: no quotes, `&&`, pipes or `$`. They become
Claude Code permission rules, and the setup action rejects anything that could
chain a second command. Put a multi-step command behind a Makefile target or a
package script. `install` is the exception: it runs as a shell command and is
never granted to agents.

## Trust

Agent workflows read the config from the default branch, not from the branch
they are working on. A PR (or the agent itself) that edits the config cannot
widen its own allowlist or unprotect a path; the change applies after it is
reviewed and merged. `pr-checks.yml` reads the PR's own copy, so a toolchain
change is tested by the PR that makes it.

## Not in the config

- **`paths:` filters** in `pr-checks.yml` and `build-image.yml`. GitHub
  evaluates them before a runner exists, so they cannot read a file. Point
  them at your source files when you adopt the kit, and keep `build-image.yml`'s
  list a superset of `image.inputs`.
- **Deploys.** The kit builds and pushes an image; it does not deploy one,
  and there is no `deploy` command. When a deploy workflow lands, its command
  gets a name here and stays off the agents' allowlist.
- **Prose facts** for the skills (review focus, threat model, trust boundary)
  live in `.claude/project-profile.md`.

## Examples

Node with pnpm:

```json
{
  "$schema": "./agent-ci.schema.json",
  "toolchain": {
    "node": { "version_file": ".nvmrc", "package_manager": "pnpm" }
  },
  "commands": {
    "install": "pnpm install --frozen-lockfile",
    "format": "pnpm prettier --write .",
    "lint": "pnpm lint",
    "typecheck": "pnpm tsc --noEmit",
    "test": "pnpm test",
    "build": "pnpm build",
    "check": ["pnpm lint", "pnpm tsc --noEmit", "pnpm test"]
  },
  "allow": ["pnpm vitest run:*"],
  "dependency_files": ["package.json", "pnpm-lock.yaml"],
  "protected_paths": ["supabase/migrations/"]
}
```

Python with uv:

```json
{
  "$schema": "./agent-ci.schema.json",
  "toolchain": {
    "python": { "version_file": ".python-version" }
  },
  "commands": {
    "install": "pip install uv && uv sync --frozen",
    "format": "uv run ruff format",
    "lint": "uv run ruff check",
    "test": "uv run pytest",
    "check": ["uv run ruff format --check", "uv run ruff check", "uv run pytest"]
  },
  "allow": ["uv run pytest:*"],
  "dependency_files": ["pyproject.toml", "uv.lock"],
  "protected_paths": ["alembic/versions/"]
}
```
