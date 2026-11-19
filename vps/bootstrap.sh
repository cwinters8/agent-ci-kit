#!/usr/bin/env bash
# Always-on agent box (optional).
#
# Turns a fresh Ubuntu 24.04 VPS (2 vCPU / 4 GB is plenty; the model runs on
# Anthropic's side, not here) into a self-hosted GitHub Actions runner with
# Claude Code installed. Point the agent workflows at it with
#   runs-on: [self-hosted, agent-box]
# and agent runs stop consuming GitHub-hosted minutes, keep a warm npm cache
# between runs, and keep going with your laptop closed.
#
# Usage (as root, once):
#   export GH_REPO=owner/repo
#   export RUNNER_TOKEN=...   # Repo -> Settings -> Actions -> Runners -> New
#                             # self-hosted runner. Expires after one hour.
#   bash bootstrap.sh
#
# Security: a self-hosted runner executes whatever a workflow tells it to. Use
# it only on a PRIVATE repo. On a public repo, a fork PR can run code on your box.
set -euo pipefail

: "${GH_REPO:?set GH_REPO=owner/repo}"
: "${RUNNER_TOKEN:?set RUNNER_TOKEN from the repo runner settings page}"
RUNNER_USER="${RUNNER_USER:-agent}"
RUNNER_LABELS="${RUNNER_LABELS:-agent-box}"
NODE_MAJOR="${NODE_MAJOR:-22}"

echo "==> Base packages"
apt-get update -y
apt-get install -y curl git jq unzip ca-certificates gnupg unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Node ${NODE_MAJOR}"
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
apt-get install -y nodejs

echo "==> GitHub CLI"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
apt-get update -y && apt-get install -y gh

echo "==> Runner user"
id "$RUNNER_USER" &>/dev/null || useradd -m -s /bin/bash "$RUNNER_USER"
RUNNER_HOME="$(getent passwd "$RUNNER_USER" | cut -d: -f6)"

echo "==> Claude Code (for interactive use over SSH; the action installs its own)"
sudo -iu "$RUNNER_USER" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

echo "==> GitHub Actions runner"
version="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')"
arch="$(uname -m)"; case "$arch" in x86_64) arch=x64;; aarch64) arch=arm64;; esac
dir="$RUNNER_HOME/actions-runner"
sudo -u "$RUNNER_USER" mkdir -p "$dir"
curl -fsSL "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-${arch}-${version}.tar.gz" \
  | sudo -u "$RUNNER_USER" tar xz -C "$dir"
"$dir/bin/installdependencies.sh"
sudo -u "$RUNNER_USER" "$dir/config.sh" --unattended \
  --url "https://github.com/${GH_REPO}" --token "$RUNNER_TOKEN" \
  --name "$(hostname)-agent" --labels "$RUNNER_LABELS" --replace
(cd "$dir" && ./svc.sh install "$RUNNER_USER" && ./svc.sh start)

echo "==> Done. Runner '$(hostname)-agent' registered with labels: $RUNNER_LABELS"
echo "    Check: Repo -> Settings -> Actions -> Runners shows it Idle."
