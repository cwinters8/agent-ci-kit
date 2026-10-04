# Always-on agent box (bonus)

GitHub-hosted runners already run with your laptop closed. A VPS earns its keep
for three other reasons:

1. **Minutes.** Private repos get a monthly allowance of GitHub-hosted minutes.
   An agent run that installs dependencies and runs checks for 10 to 20 minutes
   burns through it fast. A self-hosted runner's minutes are free; you pay the
   flat VPS price.
2. **Warm cache.** `node_modules`, the npm cache and toolchains stay on disk
   between runs, so each run starts faster.
3. **A box you can SSH into** and run `claude` interactively against the same
   checkout the agents use, from your phone if you have to.

## Setup

```sh
export GH_REPO=owner/repo
export RUNNER_TOKEN=...   # Settings -> Actions -> Runners -> New self-hosted runner
sudo -E bash bootstrap.sh
```

Then, in the agent workflows, change `runs-on: ubuntu-latest` to:

```yaml
runs-on: [self-hosted, agent-box]
```

Leave `pr-checks.yml` on GitHub-hosted runners: CI should run on a clean machine.

## Rules

- **Private repos only.** A self-hosted runner executes whatever a workflow
  says. On a public repo a fork PR can run code on your server.
- One runner runs one job at a time. Two agent runs queue rather than run in
  parallel, which doubles as a concurrency cost control.
- The box holds no Anthropic credential. Secrets arrive per job from GitHub.
