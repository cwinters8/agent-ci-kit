# Guardrails

What stops an unattended agent from doing damage, and exactly how far each
control reaches. Most rows are YAML you can read rather than instructions the
model may ignore. The one control that actually keeps agent work off your
default branch is branch protection, which lives in your repo settings, not in
this kit: `/adopt-kit` installs it and `/adopt-kit doctor` checks it.

| Guardrail | What enforces it, and where it stops |
| --- | --- |
| Only maintainers can start a run | The action checks that whoever applied the label or wrote the `@claude` comment is a human with write access, and stops otherwise. Applying a label needs only the triage role, so a triage user's `agent:fix` label still starts a short run the action then refuses, and that run counts toward the daily fix cap. `claude-code-review.yml` runs on every push to a ready same-repo PR, which also needs write access; fork PRs are skipped |
| Changes to CI, agent config or secrets don't reach a PR unseen | `claude-fix-issue.yml` only: after the agent pushes, the `Guardrails` step diffs the run's branch and refuses to open a PR if it touches `.github/`, `.claude/`, `.env*` or a `protected_paths` entry in `.claude/agent-ci.json` (the config can add paths, never remove the fixed three). It labels the issue `agent:needs-human` and leaves the branch for you to inspect. It checks only that branch, after the push, so it flags a change rather than preventing it. `claude.yml` and the review sweep have no path check. Their pushes normally go to the PR branch you review, but `git push` can name any branch, so a push could land on a branch with no PR. What stops any of it reaching the default branch is branch protection with code owner review |
| Large diffs are flagged | `claude-fix-issue.yml` labels diffs over `AGENT_MAX_DIFF_LINES` with `agent:large-diff` |
| No web tools | `--disallowedTools WebFetch,WebSearch` takes away the agent's own browsing, which cuts the easy route for prompt injection from fetched pages. It is not network isolation: the runner's network is open, and an allowlisted check (`make check`, `go test`) runs code the agent can write, which can reach the internet |
| Agent can only run listed commands | `--allowedTools` is built from the named `commands` and `allow` in `.claude/agent-ci.json`, read from the default branch so a PR cannot widen it, plus the `git` subcommands each workflow lists and, in the sweep, `gh pr` subcommands, `gh api` and `gh run`. Emptying `allow` removes none of those. Anything else is denied in a headless run. A listed check still runs whatever code the branch holds, including code the agent wrote, so the list bounds the commands typed, not the code that runs |
| Agent never merges or pushes to main | Branch protection on the default branch: a ruleset requiring a pull request and a code owner's approval. `/adopt-kit doctor` fails without it. No workflow grants `gh pr merge` and `git` is allowed by named subcommand only, but that is defense in depth: `git push` can name the default branch, the sweep keeps `gh api` (which reaches the merge endpoint), and its `AGENT_PR_TOKEN` can write |
| Fix PRs open as drafts | The fix workflow opens its PR with `gh pr create --draft`; that agent never opens it. The sweep's agent opens its own `-review-fixes` side PRs and can mark PRs ready (`gh pr create`, `gh pr ready`); those are drafts only because the `review-sweep` skill says so |
| Credentials are step-scoped | Secrets are passed to the step that needs them, never a job-level `env:`. The sweep's agent step does get `AGENT_PR_TOKEN`, so its fix pushes trigger CI |

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
  PAT there, a prompt-injected sweep could merge, or push straight to the
  default branch, through `gh api` or `git push`, past the gate. On a public repo, either run the sweep only on PRs whose comments you
  have read, or put a second, non-admin account's PAT in `AGENT_PR_TOKEN`
  (README Quickstart step 5).
- Only label issues `agent:fix` after reading their title and body. The
  labeler must have write access, but whoever filed the issue wrote the text
  the agent follows.
- Only `@claude` on PRs whose authors you trust. The run installs the PR's
  dependencies and runs its checks, so the PR's own code (install hooks,
  tests, Makefile) executes in a job that can push. On a private repo every
  PR author already has write access; on a public one, a fork PR does not.
