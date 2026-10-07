# 1. GitHub: account and SSH key

The group keeps its settings, job templates and these pages in **git** repositories on
**GitHub**. git records the history of a folder of files: every saved state (a *commit*)
can be compared with, or restored from, any other, and several people can work on the same
files without overwriting each other. GitHub hosts the shared copy of such a folder (a
*repository*) and is where changes are reviewed. The group repository is
**[IdroboLab/idrobolab-env](https://github.com/IdroboLab/idrobolab-env)**; your own
analysis code belongs in git too ([page 2](02-cloning.md#5-your-own-projects-and-your-data)).

This page sets up what every later page assumes: a GitHub account, membership of the
IdroboLab organisation, an SSH key that lets git on your laptop identify you, and git's
one-time settings. Cloning repositories is the next page ([page 2](02-cloning.md)); getting
the same access on Perlmutter is in
[Perlmutter page 2](perlmutter/02-shell-setup.md#1-github-from-perlmutter).

## 1. Account and the IdroboLab organisation

1. Create an account at <https://github.com> (or use the one you have).
2. Turn on two-factor authentication: profile picture → **Settings** → **Password and
   authentication** → **Enable two-factor authentication**. Scan the QR code with an
   authenticator app, enter the six-digit code, and store the recovery codes somewhere safe:
   they get you back into your account if you lose the phone.
3. Send the maintainer your GitHub username. He adds you to the **IdroboLab** organisation, and with
   it to `idrobolab-env`, which is private. GitHub emails you an invitation with a link;
   click it to accept.

## 2. An SSH key for GitHub

git talks to GitHub over SSH with a key pair: the **private key** stays on your machine
and is never shared, and the **public key** (the file ending in `.pub`) is registered on
GitHub. This is a different key from the 24-hour NERSC key from `sshproxy`.

**Create the key on your laptop** (PowerShell on Windows, a terminal elsewhere):

```bash
ssh-keygen -t ed25519 -C "<your email>"
```

Press Enter to accept the file name `~/.ssh/id_ed25519` (on Windows
`C:\Users\<you>\.ssh\id_ed25519`), and choose a passphrase. This writes the private key
`id_ed25519` and the public key `id_ed25519.pub`.

**Register the public key** on GitHub: profile picture → **Settings** → **SSH and GPG
keys** → **New SSH key**. Give it a title such as "laptop", leave the key type at
**Authentication Key**, and paste the contents of the `.pub` file into **Key**:

```bash
cat ~/.ssh/id_ed25519.pub                              # Linux, macOS
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub        # Windows PowerShell
```

**Test it:**

```bash
ssh -T git@github.com
```

The first time, ssh shows GitHub's host key fingerprint and asks whether to continue.
Compare it with the fingerprints GitHub publishes at
<https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints>
(the Ed25519 one starts `SHA256:+DiY3wvv`), then type `yes`. The answer
"Hi <username>! You've successfully authenticated, but GitHub does not provide shell
access." means it works.

**Tokens instead of keys.** GitHub also accepts HTTPS with a personal access token
(**Settings → Developer settings → Personal access tokens**). We use SSH; a token is a
password, so never paste it into a file, a script or an AI prompt.

## 3. git, once

On every machine where you use git (your laptop, and Perlmutter):

```bash
git config --global user.name "Your Name"
git config --global user.email "<the email on your GitHub account>"
git config --global pull.rebase true        # keep history linear when pulling
git config --global init.defaultBranch main
```

`user.name` and `user.email` are written into every commit you make.
