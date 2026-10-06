# 9. Coding agents: Claude Code and Codex

NERSC supports two AI coding agents on Perlmutter and documents both:

- **Claude Code** (Anthropic): <https://docs.nersc.gov/development/coding-agents/claude-code/>
- **Codex** (OpenAI): <https://docs.nersc.gov/development/coding-agents/codex/>
- Overview and rules: <https://docs.nersc.gov/development/coding-agents/>

An agent reads and edits files and runs commands **as you**: with your account, your
files and your allocation. NERSC's rule is that you are responsible for everything it
does, so don't let it do anything you wouldn't do yourself.

## Install and log in (on a login node, from `$HOME`)

| | Claude Code | Codex |
|---|---|---|
| Account | Claude Pro, Max, Team, Enterprise or Console (not the free plan) | ChatGPT account (the free plan includes limited use) |
| Install | `curl -fsSL https://claude.ai/install.sh \| bash` | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` |
| Log in | run `claude`, press `c` to copy the login URL, open it in your laptop's browser, paste the code back | `codex login --device-auth`; or connect with `ssh -L 1455:localhost:1455 perlmutter` and open the printed URL locally |
| Start | `claude` in your project folder | `codex` in your project folder |

For Codex, [codex.md](codex.md) walks through every step.

Both also have editor and desktop-app versions that connect to Perlmutter over SSH.
On Perlmutter, the terminal version is the simplest.

## NERSC's baseline instructions

NERSC publishes instruction files that teach an agent Perlmutter's rules: login nodes
vs jobs, Slurm, file systems. Install them once:

```bash
git clone https://github.com/NERSC/coding-agents.git ~/nersc-coding-agents
```

Then follow `claude/README.md` or `codex/README.md` in that clone. They install
`~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md`. `git pull` there picks up NERSC's
updates. For one project, put a `CLAUDE.md` or `AGENTS.md` in the project folder (`/init`
inside the agent drafts one) with what the agent should know about that project.

For Codex, NERSC recommends this `~/.codex/config.toml`:

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"
```

## Rules

- **Small things on the login node, everything else as a job.** Let the agent edit,
  run git and run quick checks. Tests, simulations and anything long go through
  `salloc`/`sbatch` ([page 4](04-jobs.md)), and every allocation charges <project>. Approve
  each one yourself, with the account, QOS, GPU count and time limit in view.
- **Keep the safety prompts on.** Approve commands as they come; don't start Claude
  Code with `--dangerously-skip-permissions`, or Codex with `danger-full-access` or a
  sandbox bypass.
- **The filesystem guard.** Since August 2026, NERSC blocks agents from scanning broad
  directory trees (`find /global/cfs ...`, `grep -r` over `/pscratch`, …). When the
  agent is blocked, the fix is a narrower directory, never a different command that
  does the same scan.
- **Shared data.** Other people's files on CFS are theirs: the agent must not delete,
  move or change their permissions.
- **Secrets and data.** Never paste passwords, tokens or private keys into a prompt.
  NERSC advises against sending unpublished research data to external AI services;
  when in doubt, ask the maintainer before an agent reads collaborators' data.
- **Notes outlive the conversation.** Agents forget long sessions. Have them write
  plans and findings into Markdown files in the project, and commit those with git.
- **Check the results.** Review diffs before committing, and check numbers against
  something you trust.
