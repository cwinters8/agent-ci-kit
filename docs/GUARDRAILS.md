# Guardrails

What stops an unattended agent from doing damage, enforced by YAML rather than
by asking the model nicely.

| Guardrail | Enforced by |
| --- | --- |
| Only maintainers can start a run | label/comment triggers need write access; the action re-checks that the actor is a human with write access |
| Agent never touches CI, agent config or secrets | `Guardrails` step refuses to open a PR if the diff touches `.github/`, `.claude/`, `.env*` or a `protected_paths` entry in `.claude/agent-ci.json`, and labels the issue `agent:needs-human`. The config can add paths, never remove the fixed three |
| Review bots cannot spend at will | `claude-review-respond.yml` starts only for maintainers and bots in `AGENT_REVIEW_BOTS`, only on agent branches, and never for `claude[bot]`, so the agent's own replies cannot loop |
| Large diffs are flagged | diffs over `AGENT_MAX_DIFF_LINES` get `agent:large-diff` |
| Agent cannot browse the web | `--disallowedTools WebFetch,WebSearch` (blocks prompt injection from fetched pages and data exfiltration by URL) |
| Agent can only run listed commands | `--allowedTools` allowlist built from the named `commands` and `allow`, read from the default branch so a PR cannot widen it; anything else is denied in a headless run |
| Agent never merges or pushes to main | no merge tool granted; branch protection on main (set this up) |
| PRs open as drafts | `gh pr create --draft` in the workflow |
| Credentials are step-scoped | secrets passed to the action step only, never a job-level `env:` |

## Before enabling on a public repo

The defaults assume a private repo where every commenter is you or a bot you
installed. On a public repo:

- Keep `allowed_non_write_users` unset (the default). Never set it to `*`.
- Disable the `claude-review-sweep.yml` schedule, or restrict it to PRs by
  maintainers: it reads review text from anyone and can push.
  `claude-review-respond.yml` only starts for maintainers and listed bots,
  and tells the agent to skip comments from anyone else. That filter is an
  instruction to the model, not enforcement, so a stranger's comment on an
  agent PR can still reach it. Disable it too unless you accept that.
- Never point agent workflows at a self-hosted runner (see `vps/README.md`).
- Turn on branch protection requiring review on the default branch.
- Only `@claude` on PRs whose authors you trust. The run installs the PR's
  dependencies and runs its checks, so the PR's own code (install hooks,
  tests, Makefile) executes in a job that can push. On a private repo every
  PR author already has write access; on a public one, a fork PR does not.
