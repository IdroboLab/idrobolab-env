# GitHub and git

The group keeps its settings, job templates and these pages in the git repository
**[IdroboLab/idrobolab-env](https://github.com/IdroboLab/idrobolab-env)** on GitHub.
Each member works in their own copy (a *clone*) and proposes changes through pull
requests ([contributing](CONTRIBUTING.md)). This page sets up GitHub access from your
laptop and from Perlmutter; do it after logging in to Perlmutter the first time
([Perlmutter page 1](../perlmutter/docs/01-login.md)).

## 1. Account and the IdroboLab organisation

1. Create an account at <https://github.com> (or use the one you have).
2. Turn on two-factor authentication: **Settings → Password and authentication**.
3. Send the maintainer your GitHub username. He adds you to the **IdroboLab** organisation, and
   with it to `idrobolab-env`, which is private.

## 2. An SSH key for GitHub

git talks to GitHub over SSH with a key pair: the private key stays on your machine,
and the public key is registered on GitHub. This is a different key from the 24-hour
NERSC key from `sshproxy`.

**On your laptop** (PowerShell on Windows, a terminal elsewhere):

```bash
ssh-keygen -t ed25519 -C "<your email>"
```

Press Enter to accept the file name `~/.ssh/id_ed25519`, and choose a passphrase. This
writes the private key `id_ed25519` and the public key `id_ed25519.pub`.

**Register the public key** on GitHub: **Settings → SSH and GPG keys → New SSH key**.
Paste the contents of the `.pub` file there and give it a title such as "laptop":

```bash
cat ~/.ssh/id_ed25519.pub                              # Linux, macOS
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub        # Windows PowerShell
```

**Test it:** `ssh -T git@github.com` should answer "Hi <username>! You've successfully
authenticated". The first time, confirm GitHub's host key with `yes`.

## 3. GitHub from Perlmutter

There are two ways. Start with A; switch to B if you work from ThinLinc. Under both,
git that needs your key runs on a login node: compute nodes have neither your key nor
your agent.

**A. Forward your laptop's key (no key stored at NERSC).** The `ForwardAgent yes` line
in your SSH config ([Perlmutter page 1](../perlmutter/docs/01-login.md#4-ssh-config)) lets git on Perlmutter use the
laptop's key while you are connected. Load the key into your laptop's agent once per
login session:

```bash
ssh-add ~/.ssh/id_ed25519            # Linux; macOS: ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

```powershell
# Windows, once, in an *administrator* PowerShell: start the agent service
Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent
# then, as yourself
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

Then, on Perlmutter, `ssh -T git@github.com` should greet you. While you are connected,
anyone with root on the remote machine could use your forwarded agent. That is
acceptable at NERSC, but don't forward your agent to machines you don't trust.

**B. A separate key on Perlmutter.** Run the same `ssh-keygen` command on a Perlmutter
login node, **with a passphrase**, and register that public key on GitHub too, with a
title such as "perlmutter".

**Tokens instead of keys.** GitHub also accepts HTTPS with a personal access token
(**Settings → Developer settings → Personal access tokens**). We use SSH; a token is a
password, so never paste it into a file, a script or an AI prompt.

## 4. git, once

On every machine where you use git:

```bash
git config --global user.name "Your Name"
git config --global user.email "<the email on your GitHub account>"
git config --global pull.rebase true        # keep history linear when pulling
git config --global init.defaultBranch main
```

## 5. Your copy of idrobolab-env

On Perlmutter ([shell setup](../perlmutter/docs/02-shell-setup.md) uses it next):

```bash
git clone git@github.com:IdroboLab/idrobolab-env.git ~/idrobolab-env
```

Keep it up to date with `git -C ~/idrobolab-env pull`.

## 6. Everyday git

```bash
git status                         # what changed?
git diff                           # the changes themselves
git add <file>                     # stage a change
git commit -m "Short description"  # record it
git pull                           # get others' changes (rebases yours on top)
git push                           # publish your commits
git log --oneline -10              # recent history
```

To change `idrobolab-env` itself, open a pull request: see
[contributing](CONTRIBUTING.md).

Your own projects (analysis code, job scripts) belong in git too. Create them under
your GitHub account or in IdroboLab (ask first). Keep data out of git: large files,
simulation output and raw microscope data stay on CFS
([Perlmutter page 3](../perlmutter/docs/03-storage-and-transfer.md)), and a `.gitignore` file keeps them from being
committed by accident.
