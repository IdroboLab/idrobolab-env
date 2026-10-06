# 10. Coding agents: Claude Code and Codex

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

## Instructions: three layers

An agent follows three layers of written instructions, each adding to the one before:

1. **NERSC's baseline**: what an agent must know about Perlmutter (login nodes vs
   jobs, Slurm approval, file systems, the filesystem guard). It is kept in this repo
   under `perlmutter/agents/nersc/`. NERSC's updates arrive as a pull request from a
   weekly workflow, and an admin reads them before they reach you.
2. **The group's rules**: [`perlmutter/agents/group.md`](../agents/group.md): accounts,
   queues, container, data and provenance. They never relax NERSC's.
3. **The project's own**: a `CLAUDE.md` or `AGENTS.md` in the project folder (`/init`
   inside the agent drafts one) with what the agent should know about that project.

One command sets up layers 1 and 2 for both agents; run it once, and again after
every `git pull` of `~/idrobolab-env`:

```bash
~/idrobolab-env/perlmutter/helpers/setup-agents.sh           # set up or update
~/idrobolab-env/perlmutter/helpers/setup-agents.sh --check   # report only
~/idrobolab-env/perlmutter/helpers/setup-agents.sh --undo    # remove what it added
```

- **Claude Code**: a marked block at the top of `~/.claude/CLAUDE.md` imports the two
  files from your clone, so a `git pull` is all an update needs. Your own text goes
  below the block. If you pasted NERSC's file into `CLAUDE.md` earlier, the script
  warns: delete that part by hand, or it loads twice.
- **Codex** cannot import files, so the script writes a copy of both between markers
  at the top of `~/.codex/AGENTS.md`, then a `## Local additions` heading and your own
  text. After a `git pull`, run the script again (`--check` and `setup-user.sh` say
  when the copy is stale). Text you already had below `## Local additions` is kept, and
  a file with no such heading moves below one; the first time, the old file is backed up
  next to it.
- `CLAUDE_CONFIG_DIR` and `CODEX_HOME` are honoured. A Claude config file inside a git
  work tree is never edited: the script prints the lines to add by hand.
- Restart the agent afterwards.

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
