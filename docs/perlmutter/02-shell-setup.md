# 2. Shell and group setup

One-time setup on a Perlmutter login node: git access to GitHub, your clone of
`idrobolab-env`, a nicer prompt (optional), then the group environment. It builds on the
GitHub account and SSH key from the [GitHub page](../01-github.md). **Do the steps in
this order.** The oh-my-bash installer replaces `~/.bashrc`, which would remove the line
the group setup adds. If you did it the other way round, just re-run the group setup.

## 1. GitHub from Perlmutter

There are two ways. Start with A; switch to B if you work from ThinLinc. Under both,
git that needs your key runs on a login node: compute nodes have neither your key nor
your agent.

**A. Forward your laptop's key (no key stored at NERSC).** The `ForwardAgent yes` line
in your SSH config ([page 1](01-login.md#4-ssh-config)) lets git on Perlmutter use the
laptop's key while you are connected. The key has to be loaded in your laptop's agent
first, once per login session: with the `Host github.com` entry from the
[GitHub page](../01-github.md#3-the-ssh-config-entry-for-githubcom) a `ssh -T git@github.com`
on the laptop does it, and the same page explains the agent and `ssh-add`. Then log in to
Perlmutter. `ssh-add -l` there lists the forwarded key, and `ssh -T git@github.com`
should greet you. While you are connected, anyone with root on the remote machine could
use your forwarded agent. That is acceptable at NERSC, but don't forward your agent to
machines you don't trust.

Under A, **do not add a `Host github.com` entry on Perlmutter**, and above all not the
laptop's: `IdentitiesOnly yes` restricts ssh to the key files the entry names, even when
the agent offers more (`man ssh_config`), and the laptop's `IdentityFile` does not exist on
Perlmutter, so the forwarded key would never be offered. Without an entry, ssh offers
the forwarded agent's keys.

**B. A separate key on Perlmutter.** Run the same `ssh-keygen` command on a Perlmutter
login node ([GitHub page](../01-github.md#2-an-ssh-key-for-github)), **with a
passphrase**, and register that public key on GitHub too, with a title such as
"perlmutter". No config entry is needed: ssh tries `~/.ssh/id_ed25519` by default. If
you keep several keys in `~/.ssh` on Perlmutter, add this to `~/.ssh/config` there, so
that only the GitHub key is offered:

```
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Set git's name and e-mail here as well, once
([the GitHub page](../01-github.md#4-git-once)).

## 2. Your clone of idrobolab-env

```bash
git clone git@github.com:IdroboLab/idrobolab-env.git ~/idrobolab-env
```

Everything below uses this clone, and so does your shell once the group setup has run.
Cloning in general: [the cloning page](../02-cloning.md).

## 3. oh-my-bash (optional)

[oh-my-bash](https://github.com/ohmybash/oh-my-bash) gives bash a themed prompt (git
branch, exit status, …), better tab completion and handy aliases.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
```

- The installer moves your current `~/.bashrc` to `~/.bashrc.omb-backup-<timestamp>`
  and writes a new one. Copy over anything you had added yourself (aliases,
  `module load`, `PATH` changes).
- **Theme:** set `OSH_THEME="..."` in `~/.bashrc` (the default is `font`; see
  `ls ~/.oh-my-bash/themes`), then run `source ~/.bashrc`. Themes such as `agnoster`
  need a Powerline font in your *local* terminal.
- The new `~/.bashrc` begins with a `case $- in` block that stops non-interactive
  shells (scripts, `scp`, `rsync`, `ssh perlmutter <command>`, coding agents) from
  reading the rest, including the group block that section 4 appends at the end. If you
  need the group environment there, move that block (from `# >>> hpcenvs` to
  `# <<< hpcenvs`) above the `case` line. Batch jobs are unaffected: they inherit the
  environment of the shell you submit from.
- If the prompt becomes slow inside large git repositories, switch to a theme that
  doesn't show git status.
- To undo: run `uninstall_oh_my_bash`, which restores the backup.

## 4. Group environment

Run the group setup script once:

```bash
~/idrobolab-env/perlmutter/helpers/setup-user.sh
```

The script:

1. Adds a short, marked block to `~/.bashrc` that sources the group's
   [`env.sh`](../../perlmutter/env.sh).
2. Links the group's shared Jupyter kernels into your account
   ([page 8](08-jupyter.md)).
3. Checks the things that otherwise break later: that you are in the `<project>` group,
   that you can read the shared container store, and that `$SCRATCH` exists.
4. Writes `~/perlmutter.code-workspace`, the VS Code workspace with your home directory,
   the project's CFS tree and `$SCRATCH` ([page 11](11-vscode.md#4-one-window-for-home-projects-and-scratch)),
   unless that file already exists.

On the first run, a warning that `PODMANHPC_ADDITIONAL_STORES` is unset is expected:
the new settings only apply to shells started afterwards. Log out, log in again, and
confirm with `--check`, which only reports and changes nothing:

```bash
~/idrobolab-env/perlmutter/helpers/setup-user.sh --check
```

Re-run the script any time; it is safe to repeat. `--undo` removes the block again
(it leaves the workspace file, which is yours).

**If you used the old shared checkout** (`/global/cfs/cdirs/<project>/env`), the script
reports that your `~/.bashrc` block points "somewhere else". Switch it to your clone:

```bash
~/idrobolab-env/perlmutter/helpers/setup-user.sh --undo
~/idrobolab-env/perlmutter/helpers/setup-user.sh
```

After the setup, every shell has:

| What | Use |
|---|---|
| `uv` on `PATH` | Python environments ([page 5](05-python-uv.md)) |
| `UV_CACHE_DIR`, `UV_PYTHON_INSTALL_DIR` | uv's cache on `$SCRATCH`, Python interpreters in the group software dir |
| `PODMANHPC_ADDITIONAL_STORES`, `$IDROBOLAB_IMAGE` | the group container store and image ([page 6](06-containers.md)) |
| `cds` / `cdp` | `cd` to your `$SCRATCH` / the group project dir `/global/cfs/cdirs/<project>/projects` |
| `q` / `sr` / `sp` | your jobs: all / running / pending |

The script doesn't touch anything else in `~/.bashrc`, so you can keep your own
additions there. NERSC's old `~/.bashrc.ext` files are deprecated; if the script warns
about one, move its contents into `~/.bashrc`.

## 5. Keeping your clone current

Everything in these pages (job templates, helper scripts, `env.sh`, the container
recipe) lives in your clone `~/idrobolab-env`, and your shell reads `env.sh` from there.
Update it now and then, and when someone announces a change
([keeping a clone up to date](../02-cloning.md#3-keeping-a-clone-up-to-date)):

```bash
git -C ~/idrobolab-env pull
```

To change something for everyone, use a branch and a pull request
([contributing](../CONTRIBUTING.md)).

## 6. Checking your setup

A script checks the setup on this page, and the coding-agent rules once you have set
them up ([page 10](10-coding-agents.md)). Run it on a login node after the setup, after
a `git pull`, after moving your clone, or whenever something behaves oddly:

```bash
~/idrobolab-env/perlmutter/helpers/check-setup.sh
```

It never prompts and changes no file outside your clone's `.git` directory, where its
`git fetch` updates what git knows about GitHub. It prints `OK`, `NOTE` and `FAIL`
lines in three sections:

| Section | What it checks |
|---|---|
| 1. this clone | its remote and branch; whether it is behind or ahead of GitHub (as of the last fetch that worked, if this one fails); uncommitted changes. A branch other than `main` gets a note, because your shell reads `env.sh` from whatever is checked out |
| 2. shell | the output of `setup-user.sh --check` ([section 4](#4-group-environment)), which includes `setup-agents.sh --check` once you have run that; whether `env.sh` is active in this shell; whether `$IDROBOLAB_IMAGE` is the image this clone's `env.sh` gives |
| 3. leftovers | paths to another idrobolab-env or hpcenvs clone (including renamed copies such as `idrobolab-env.old`), or to the old shared checkout `/global/cfs/cdirs/<project>/env`, in your shell startup files, git and ssh config, crontab and scrontab, `~/bin`, `~/.local/bin`, your Jupyter kernels and your agents' instruction files; links up to three levels below your home directory that point there or nowhere |

A `FAIL` needs fixing; the line says where. The script exits with status 1 when it
printed one. A `NOTE` is information that may need action. Two are common:

- **`IDROBOLAB_IMAGE=... but this clone's env.sh gives ...`**: `env.sh` keeps a value
  that is already set, so a shell that started before a `git pull` keeps the old image
  name. Log out and in again.
- **`N commit(s) behind GitHub`**: run the `git pull` the line shows
  ([section 5](#5-keeping-your-clone-current)).
