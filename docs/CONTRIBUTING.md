# Contributing

Everyone in the group can improve this environment: a clearer page, a fixed job
template, a new helper script, a setting that should change for everyone. **Every change
reaches `main` through a pull request (PR).** Nobody pushes to `main` directly, admins
included; admins merge the PRs. GitHub cannot enforce this on our plan, so it is a rule we
keep ourselves: everything in `main` reaches every member's shell and jobs on their next
`git pull`, so each change is read by someone else first.

## How to propose a change

You need access to the repository and an SSH key ([GitHub and git](github.md)).

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
   changed, why, and how you tried it. An admin reviews it, may ask for changes (push
   more commits to the same branch), and merges it.

5. Afterwards, go back to `main` and update:

   ```bash
   git -C ~/idrobolab-env switch main
   git -C ~/idrobolab-env pull
   ```

Not sure how to change something, or only want to point out a problem? Open an
**issue** on GitHub instead, or ask the maintainer.

## What makes a change easy to merge

- **One topic per PR.** A page fix and a new job template are two PRs.
- **Try it on Perlmutter** before opening the PR: run the script, or submit the job
  template with a short time limit, and say in the PR what you ran. For a page, follow
  the commands you changed: they must be complete and pasteable.
- **Keep pages short** and in the order a newcomer needs them. When you rename or add a
  page, update the links and the table in
  [perlmutter/docs/README.md](../perlmutter/docs/README.md).
- **`perlmutter/env.sh` is sourced by every member's shell**: it must stay silent, never
  stop a shell (no `exit`, no `set -e`), and keep a setting someone has already chosen.
  Changes here get the closest review.
- **Shared software** (the container image, shared Python and `uv`, Jupyter kernels,
  Nion Swift) is installed by the maintainer. Propose the change in a PR or an issue;
  don't install into `/global/common/software/<project>` yourself.

## What never goes into the repository

- Data, simulation output, job logs, images and other large files: they belong on CFS
  ([Perlmutter page 3](../perlmutter/docs/03-storage-and-transfer.md)).
- Passwords, tokens, private keys, the `sshproxy` key, anything from `~/.ssh`.
- Personal settings that only make sense for you. Put those in your own `~/.bashrc`.

## Rules for members' coding agents

`perlmutter/agents/group.md` holds the group's rules for Claude Code and Codex: change
it by pull request like anything else. NERSC's own baseline is vendored in
`perlmutter/agents/nersc/` and is never edited by hand: a weekly workflow
(`nersc-agents-sync`) opens one pull request when NERSC's
[coding-agents](https://github.com/NERSC/coding-agents) repository changes, and an
admin reads the diff before merging it, because every member's agents follow that text.
For an admin: the workflow needs "Allow GitHub Actions to create and approve pull
requests" switched on (repository or organisation *Settings → Actions → General →
Workflow permissions*). It can also be started from the Actions tab. GitHub disables a
scheduled workflow after 60 days without repository activity; re-enable it under
Actions.

Code written with a coding agent is welcome; you are responsible for it like any other
code, so read it before opening the PR. Agents working in this repo follow its
[AGENTS.md](../AGENTS.md); add rules for them there
([Perlmutter page 10](../perlmutter/docs/10-coding-agents.md)).
