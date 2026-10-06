# 2. Shell and group setup

One-time setup on a Perlmutter login node: a nicer prompt (optional), then the group
environment. **Do them in this order.** The oh-my-bash installer replaces `~/.bashrc`,
which would remove the line the group setup adds. If you did it the other way round,
just re-run the group setup.

## 1. oh-my-bash (optional)

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
  shells (scripts, `scp`, `rsync`) from reading the rest. Settings a script needs must
  go above that block.
- If the prompt becomes slow inside large git repositories, switch to a theme that
  doesn't show git status.
- To undo: run `uninstall_oh_my_bash`, which restores the backup.

## 2. Group environment

Run the group setup script once:

```bash
/global/cfs/cdirs/<project>/env/perlmutter/helpers/setup-user.sh
source ~/.bashrc
```

The script:

1. Adds a short, marked block to `~/.bashrc` that sources the group's
   [`env.sh`](../env.sh).
2. Links the group's shared Jupyter kernels into your account
   ([page 7](07-jupyter.md)).
3. Checks the things that otherwise break later: that you are in the `<project>` group,
   that you can read the shared container store, and that `$SCRATCH` exists.

On the first run, a warning that `PODMANHPC_ADDITIONAL_STORES` is unset is expected:
the new settings only apply to shells started afterwards. After `source ~/.bashrc`,
confirm with `--check`, which only reports and changes nothing:

```bash
/global/cfs/cdirs/<project>/env/perlmutter/helpers/setup-user.sh --check
```

Re-run the script any time; it is safe to repeat. `--undo` removes the block again.

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

## 3. The settings repository

Everything in these pages (job templates, helper scripts, `env.sh`, container
recipes) lives in the git repository **hpcenvs**. The `perlmutter/` and `shared/`
folders are checked out for the whole group at

```
/global/cfs/cdirs/<project>/env
```

That checkout is all most people need. You can read, run and copy from it, but **don't
edit, commit or `git pull` there**: it is shared, and the maintainer updates it.

**Your own clone** is only needed if you want to propose changes. The GitHub
repository (`<username>/hpcenvs`) is private, so ask the maintainer for access first. Then, with
GitHub access set up ([page 1, §6](01-login.md#6-github-from-perlmutter-optional)):

```bash
git clone --filter=blob:none --sparse git@github.com:<username>/hpcenvs.git ~/hpcenvs
git -C ~/hpcenvs sparse-checkout set shared perlmutter
git -C ~/hpcenvs config pull.rebase true
```

To make your shell use your clone instead of the shared checkout:

```bash
/global/cfs/cdirs/<project>/env/perlmutter/helpers/setup-user.sh --undo
~/hpcenvs/perlmutter/helpers/setup-user.sh
```
