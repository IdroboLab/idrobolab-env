# 2. Cloning repositories

A **clone** is your own full copy of a repository on your machine: all files and the whole
history, plus a remembered address of the original on GitHub, called `origin`. You work in
the clone and exchange commits with GitHub in both directions. This page covers cloning,
keeping a clone up to date, the everyday commands, and how to put your own projects in git.
It assumes the SSH key from [general page 1](01-github.md).

## 1. Clone a repository

On the repository's GitHub page, the green **Code** button → **SSH** tab shows its address,
of the form `git@github.com:<owner>/<repository>.git`. Clone it into a folder of your
choice, ideally somewhere that is not synchronised by a cloud service:

```bash
git clone git@github.com:<owner>/<repository>.git            # creates ./<repository>
git clone git@github.com:<owner>/<repository>.git code/x     # or into a folder you name
```

Git accepts `/` in paths on Windows. A folder name that starts with `~/` is understood by
macOS and Linux shells only: Command Prompt does not expand `~`, and Windows PowerShell
5.1 passes it to git as it is. On Windows use a relative path as above, or
`%USERPROFILE%\...` (Command Prompt) or `$env:USERPROFILE\...` (PowerShell).

Three kinds of repository come up:

- **The group's repositories** (owner `IdroboLab`, private; you need the invitation from
  [general page 1](01-github.md#1-account-and-the-idrobolab-organisation)). `idrobolab-env` holds the
  Perlmutter environment and these pages. On Perlmutter every member clones it to
  `~/idrobolab-env`
  ([Perlmutter page 2](perlmutter/02-shell-setup.md#2-your-clone-of-idrobolab-env)). To fix a page or a
  job template, clone it on your laptop as well and follow
  [contributing](CONTRIBUTING.md).
- **Your own repositories** (owner: your GitHub username): see
  [section 5](#5-your-own-projects-and-your-data).
- **Public repositories of other projects**, for example
  [abTEM](https://github.com/abTEM/abTEM): `git clone git@github.com:abTEM/abTEM.git`
  works with your key. You can read, build and run it, but you cannot push to it. To
  contribute, click **Fork** on its GitHub page (this makes a copy under your account),
  clone *your fork*, and keep the original as a second remote called `upstream`:

  ```bash
  git clone git@github.com:<your-username>/abTEM.git
  git -C abTEM remote add upstream git@github.com:abTEM/abTEM.git
  git -C abTEM remote -v                    # origin = your fork, upstream = the original
  ```

  The project's own contribution guide says which branch to start from and how it wants
  pull requests.

## 2. Looking around

```bash
git -C <clone> status             # what changed, and which branch you are on
git -C <clone> log --oneline -10  # recent history
git -C <clone> branch             # local branches; * marks the current one
git -C <clone> remote -v          # where origin points
```

`git -C <folder> <command>` runs a git command in that folder without changing directory.
Inside the clone, leave out the `-C <clone>`.

## 3. Keeping a clone up to date

```bash
git -C <clone> pull
```

fetches what others have pushed and puts your own commits on top of it (with the
`pull.rebase true` setting from [general page 1](01-github.md#4-git-once)), which keeps the
history a straight line. Update before you start working, and when someone announces a
change. `git pull` brings in the branch you are on. If it refuses because of
uncommitted changes, commit them first (next section), or look at them with
`git status` and ask before throwing anything away.

For `idrobolab-env`, an update changes the scripts and job templates your shell and jobs
use, so read what came in with `git -C ~/idrobolab-env log --oneline -5` (on Perlmutter;
on your laptop, use the folder of your clone).

## 4. Everyday git

```bash
git status                         # what changed?
git diff                           # the changes themselves
git add <file>                     # stage a change for the next commit
git commit -m "Short description"  # record it
git pull                           # get others' changes (rebases yours on top)
git push                           # publish your commits
git switch -c my-change            # start a new branch for a piece of work
git switch main                    # go back to main
```

Commit one logical change at a time, and say in the message what and why. To change
`idrobolab-env` itself, work on a branch and open a pull request:
[contributing](CONTRIBUTING.md). Never commit a password, a token or a private key
(anything from `~/.ssh`).

## 5. Your own projects and your data

Analysis code, job scripts and notes belong in git: it is your history, your backup and
the way a colleague gets the same code. Create the repository on GitHub (profile picture →
**Your repositories** → **New**; choose **Private** unless you intend to publish; the
group's repositories under IdroboLab are created after asking an admin), then put your folder
in it. First go into the folder:

### Windows

Command Prompt:

```
cd "%USERPROFILE%\myproject"
```

PowerShell:

```powershell
cd $env:USERPROFILE\myproject
```

### macOS

```bash
cd ~/myproject
```

### Linux

Same as macOS:

```bash
cd ~/myproject
```

### Put the folder in git

```bash
git init
git branch -M main
git add analysis.py README.md          # name the files; avoid `git add .` until a .gitignore exists
git commit -m "First version"
git remote add origin git@github.com:<your-username>/myproject.git
git push -u origin main
```

### Keep data out of git

Large files, simulation output, job logs and raw microscope data stay on the file
systems built for them (on Perlmutter: CFS,
[Perlmutter page 3](perlmutter/03-storage-and-transfer.md)). git keeps every version of
every file for ever, so a file committed once stays in the history even after you delete it.
GitHub warns about files above 50 MiB and blocks files above 100 MiB
([GitHub's limits](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)).
A `.gitignore` file in the top folder lists what git must leave alone:

```
# data and results
data/
results/
*.h5
*.npy
*.npz
*.dm4
# job output
slurm-*.out
*.log
```

Create it with any text editor. On Windows, `notepad .gitignore` (in either shell) opens
it by its exact name, which avoids the `.txt` extension that Notepad's Save dialog may
add.

`git status` shows what is not yet in git; check it before every `git add`. If a large
file or a secret has already been committed, stop and ask an admin before pushing.
