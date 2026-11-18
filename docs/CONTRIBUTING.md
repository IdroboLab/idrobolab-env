# Contributing

Everyone in the group can improve this environment: a clearer page, a fixed job
template, a new helper script, a setting that should change for everyone. **Every change
reaches `main` through a pull request (PR).** Nobody pushes to `main` directly, admins
included; admins merge the PRs. GitHub enforces this: a PR can be merged only once a member
of the `env-reviewers` team has approved it and its checks have passed. Everything in `main`
reaches every member's shell and jobs on their next `git pull`, so each change is read by
someone else first.

## How to propose a change

You need access to the repository and an SSH key ([GitHub](01-github.md)), and a clone
of it ([cloning](02-cloning.md)).

The commands below write the clone as `~/idrobolab-env`, which is where it is on
Perlmutter. On a laptop, use the folder of your clone. On Windows, Command Prompt does not
expand `~` and Windows PowerShell 5.1 passes it to git as it is: open the terminal in the
clone (`cd` into it) and leave out `-C ~/idrobolab-env`, or write the clone's folder with
`%USERPROFILE%` (Command Prompt) or `$env:USERPROFILE` (PowerShell).

1. Start from an up-to-date `main` and make a branch named after the change:

   ```bash
   git -C ~/idrobolab-env switch main
   git -C ~/idrobolab-env pull
   git -C ~/idrobolab-env switch -c fix-jupyter-docs
   ```

2. Make the change and commit it, with a message that says what and why, prefixed with
   the part it touches:

   ```bash
   git -C ~/idrobolab-env commit -am "jupyter: explain the GPU kernel"
   ```

3. Push the branch:

   ```bash
   git -C ~/idrobolab-env push -u origin fix-jupyter-docs
   ```

4. GitHub prints a link: open it and create the **pull request**. Describe what you
   changed, why, and how you tried it. A member of the `env-reviewers` team reviews it and
   may ask for changes (push more commits to the same branch); once it is approved and its
   checks pass, an admin merges it. A push after an approval needs a new approval, and the
   branch must be up to date with `main` before it can be merged.

5. Afterwards, go back to `main` and update:

   ```bash
   git -C ~/idrobolab-env switch main
   git -C ~/idrobolab-env pull
   ```

Not sure how to change something, or only want to point out a problem? Open an
**issue** on GitHub instead, or ask an admin.

## What makes a change easy to merge

- **One topic per PR.** A page fix and a new job template are two PRs.
- **Try it on the cluster it is for** (Perlmutter or Delta) before opening the PR: run the
  script, or submit the job template with a short time limit, and say in the PR what you ran. For a page, follow
  the commands you changed: they must be complete and pasteable.
- **Keep pages short** and in the order a newcomer needs them. When you rename or add a
  page, update the links and the tables in [README.md](README.md) and
  [perlmutter/README.md](perlmutter/README.md).
- **`perlmutter/env.sh` is sourced by every member's shell**: it must stay silent, never
  stop a shell (no `exit`, no `set -e`), and keep a setting someone has already chosen.
  Changes here get the closest review.
- **Shared software** (the container image, shared Python and `uv`, Jupyter kernels,
  Nion Swift) is installed by the maintainer. Propose the change in a PR or an issue;
  don't install into `/global/common/software/<project>` yourself.

## What never goes into the repository

- Data, simulation output, job logs, images and other large files: they belong on CFS
  ([Perlmutter page 3](perlmutter/03-storage-and-transfer.md)).
- Passwords, tokens, private keys, the `sshproxy` key, anything from `~/.ssh`.
- Personal data: names, e-mail addresses, user names, project or allocation IDs, paths with
  your user name in them. The repository is public, and a pushed branch is visible to
  everyone at once, before any review. Commit first, then check before every push: the
  check reads every tracked file of your last commit and does not see uncommitted changes.
  It prints `personal_data: 0 hit(s)` when it finds nothing:

  ```bash
  python3 ~/idrobolab-env/core/checks/personal_data.py --repo ~/idrobolab-env
  ```

  On Windows, run `python3 core/checks/personal_data.py` from inside the clone instead.
  The `personal-data` check on the pull request only keeps such data out of `main`.
- Personal settings that only make sense for you. Put those in your own `~/.bashrc`.

## Rules for members' coding agents

`perlmutter/agents/group.md` holds the group's rules for Claude Code and Codex: change
it by pull request like anything else. NERSC's own baseline is vendored in
`perlmutter/agents/nersc/` and is never edited by hand: a weekly workflow
(`nersc-agents-sync`) opens one pull request when NERSC's
[coding-agents](https://github.com/NERSC/coding-agents) repository changes, and a member
of `env-reviewers` reads the diff and approves it before an admin merges it, because every
member's agents follow that text. A pull request opened by a workflow does not start the
required checks: close and reopen it to start them.
For an admin: the workflow needs "Allow GitHub Actions to create and approve pull
requests" switched on (repository or organisation *Settings → Actions → General →
Workflow permissions*). It can also be started from the Actions tab. GitHub disables a
scheduled workflow after 60 days without repository activity; re-enable it under
Actions.

Code written with a coding agent is welcome; you are responsible for it like any other
code, so read it before opening the PR. Agents working in this repo follow its
[AGENTS.md](../AGENTS.md); add rules for them there
([Perlmutter page 10](perlmutter/10-coding-agents.md)).
