# Security policy

This kit runs AI agents in CI with repository secrets present, so a flaw in a
workflow, guardrail or setup script can matter to everyone who copied it.

## Reporting a vulnerability

Please report privately through GitHub: the **Security** tab of this repo,
then **Report a vulnerability**. Do not open a public issue for it.

Include the file and line, what an attacker needs (a fork PR, a comment, write
access), and what they get. You should hear back within a week.

## Scope

In scope: `.github/workflows/`, `.github/actions/`, `.claude/`, `setup/` and
`vps/`, and anything in `docs/GUARDRAILS.md` that the code does not actually
enforce. The sample todo API is a demo; its known gaps are listed in
`.claude/project-profile.md`.

The guardrails assume a private repo unless you follow "Before enabling on a
public repo" in `docs/GUARDRAILS.md`. A report that a private-repo default is
unsafe on a public repo is still welcome if that section misses it.
