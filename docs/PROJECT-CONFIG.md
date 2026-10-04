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
| `install` | no | `project-setup`, `session-start.sh` | Installs dependencies. Runs before the agent starts in CI and once in fresh cloud sessions. |
| `checks` | yes | `pr-checks.yml`, agents, skills | The mechanical checks, in order. CI runs each; agents must pass all of them before pushing. Prefer one entry point (`make check`, `pnpm check`) so CI and agents can never drift. |
| `agent_commands` | no | agent workflows | Commands agents may run in CI besides `checks` and git, e.g. a single test file. A trailing `:*` allows any arguments. Anything not listed is denied in a headless run. |
| `dependency_files` | no | fix agent prompt | Manifests and lockfiles. The fix agent changes them only when the bug is in a dependency. |
| `protected_paths` | no | fix workflow guardrail | Path prefixes an unattended agent may never change. The fix workflow refuses to open a PR that touches one. `.github/`, `.claude/` and `.env*` are always protected and cannot be removed. |
| `image` | no | `build-image.yml` | `inputs`: git pathspecs for everything that ends up in the image (`:!:` excludes); their content hash decides whether to build. `context` and `dockerfile` default to `.` and `Dockerfile`. Leave `image` out and delete the workflow if you ship no image. |

Commands in `checks` and `agent_commands` are single commands: no quotes,
`&&`, pipes or `$`. They become Claude Code permission rules, and the setup
action rejects anything that could chain a second command. Put a multi-step
check behind a Makefile target or a package script.

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
- **Deploys.** The kit builds and pushes an image; it does not deploy one.
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
  "install": "pnpm install --frozen-lockfile",
  "checks": ["pnpm lint", "pnpm typecheck", "pnpm test"],
  "agent_commands": ["pnpm vitest run:*", "pnpm tsc:*"],
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
  "install": "pip install uv && uv sync --frozen",
  "checks": ["uv run ruff check", "uv run pytest"],
  "agent_commands": ["uv run pytest:*", "uv run ruff format:*"],
  "dependency_files": ["pyproject.toml", "uv.lock"],
  "protected_paths": ["alembic/versions/"]
}
```
