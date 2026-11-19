# Guardrails

What stops an unattended agent from doing damage, enforced by YAML rather than
by asking the model nicely.

| Guardrail | Enforced by |
| --- | --- |
| Only maintainers can start a run | label/comment triggers need write access; the action re-checks that the actor is a human with write access |
| Agent never touches CI, agent config or secrets | `Guardrails` step refuses to open a PR if the diff touches `.github/`, `.claude/`, `.env*` or a `protected_paths` entry in `.claude/agent-ci.json`, and labels the issue `agent:needs-human`. The config can add paths, never remove the fixed three |
| Large diffs are flagged | diffs over `AGENT_MAX_DIFF_LINES` get `agent:large-diff` |
| Agent cannot browse the web | `--disallowedTools WebFetch,WebSearch` (blocks prompt injection from fetched pages and data exfiltration by URL) |
| Agent can only run listed commands | `--allowedTools` allowlist built from the named `commands` and `allow`, read from the default branch so a PR cannot widen it; anything else is denied in a headless run |
| Agent never merges or pushes to main | branch protection on main: set it up. No workflow grants `gh pr merge` and `git` is allowed by named subcommand only, but that is defense in depth: the sweep keeps `gh api` and `git push` for its job, and its token can write |
| PRs open as drafts | `gh pr create --draft` in the workflow |
| Credentials are step-scoped | secrets passed to the action step only, never a job-level `env:` |

## Before enabling on a public repo

The defaults assume a private repo where every commenter is you or a bot you
installed. On a public repo:

- Keep `allowed_non_write_users` unset (the default). Never set it to `*`.
- `claude-review-sweep.yml` skips its schedule on public repos on its own:
  it reads review text from anyone and can push. A manual run there must name
  one PR in the `pr` input, and the gate refuses fork PRs, whose checks would
  run a stranger's code with the PAT in the environment. Read that PR's
  comments before you start it.
- On a public repo anyone can post a comment shaped like the `code-review`
  clean verdict or leave a 👎. The project profile's `## Repo` section must
  tell `review-sweep` to count those only from known identities (the sample
  profile does).
- Never point agent workflows at a self-hosted runner (see `vps/README.md`).
- Set up the merge gate `/adopt-kit` installs (`setup/adopt-kit/SKILL.md`):
  a ruleset requiring a code owner's approval, with only the Repository admin
  role allowed to bypass, and a `CODEOWNERS` file naming you. "Require review
  from Code Owners" does nothing without that file.
- That admin bypass belongs to whoever holds `AGENT_PR_TOKEN`, and the sweep
  runs its agent with that token so its fix pushes trigger CI. With your own
  PAT there, a prompt-injected sweep could merge through `gh api`, past the
  gate. On a public repo, either run the sweep only on PRs whose comments you
  have read, or put a second, non-admin account's PAT in `AGENT_PR_TOKEN`
  (README Quickstart step 5).
- Only label issues `agent:fix` after reading their title and body. The
  labeler must have write access, but whoever filed the issue wrote the text
  the agent follows.
- Only `@claude` on PRs whose authors you trust. The run installs the PR's
  dependencies and runs its checks, so the PR's own code (install hooks,
  tests, Makefile) executes in a job that can push. On a private repo every
  PR author already has write access; on a public one, a fork PR does not.
