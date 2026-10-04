#!/usr/bin/env bash
# Installs the adopt-kit skill for your user, so `/adopt-kit` works in Claude
# Code in any repo on this machine. Re-run after `git pull` to update it.
#
#   bash setup/install.sh
#
# The installed skill remembers where this kit checkout lives and copies the
# kit's files from it, so keep the checkout where it is (or re-run this after
# moving it).
set -euo pipefail

kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$kit/setup/adopt-kit"
dest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/adopt-kit"

if [ ! -f "$kit/.claude/agent-ci.schema.json" ] || [ ! -f "$src/SKILL.md" ]; then
  echo "error: $kit does not look like a complete agent CI kit checkout" >&2
  exit 1
fi

# Only ever replace a directory this script created.
if [ -e "$dest" ] && [ ! -f "$dest/.installed-by-agent-ci-kit" ]; then
  echo "error: $dest exists and was not installed by this script; move it aside first" >&2
  exit 1
fi

# Build the new copy beside the old one and swap only once it is complete, so
# an interrupted update leaves the previous install working (and re-runnable).
parent="$(dirname "$dest")"
mkdir -p "$parent"
stage="$(mktemp -d "$parent/.adopt-kit.new.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
cp -R "$src/." "$stage/"
printf '%s\n' "$kit" > "$stage/kit-path"
touch "$stage/.installed-by-agent-ci-kit"
chmod 755 "$stage"

if [ -e "$dest" ]; then
  old="$(mktemp -d "$parent/.adopt-kit.old.XXXXXX")"
  mv "$dest" "$old/adopt-kit"
  mv "$stage" "$dest"
  rm -rf "$old"
else
  mv "$stage" "$dest"
fi
trap - EXIT

echo "Installed /adopt-kit to $dest (kit: $kit)"
echo "Next: open Claude Code in your project's repo and run /adopt-kit"
