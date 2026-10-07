# 1. GitHub: account and SSH key

The group keeps its settings, job templates and these pages in **git** repositories on
**GitHub**. git records the history of a folder of files: every saved state (a *commit*)
can be compared with, or restored from, any other, and several people can work on the same
files without overwriting each other. GitHub hosts the shared copy of such a folder (a
*repository*) and is where changes are reviewed. The group repository is
**[IdroboLab/idrobolab-env](https://github.com/IdroboLab/idrobolab-env)**; your own
analysis code belongs in git too ([page 2](02-cloning.md#5-your-own-projects-and-your-data)).

This page sets up what every later page assumes: a GitHub account, membership of the
IdroboLab organisation, an SSH key that lets git on your laptop identify you (with the config entry that goes with it),
and git's one-time settings. Cloning repositories is the next page ([page 2](02-cloning.md)); getting
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

## 3. The SSH config entry for github.com

ssh reads its per-user settings from a **config file**; one entry in it makes every git
command that talks to `github.com` use the key from section 2, and load it into your SSH
agent (below) so that you type the passphrase once per login session. Without the entry,
ssh still tries the default key file `~/.ssh/id_ed25519`, so everything works, but the
entry is what you want once you have more than one key.

| OS | The config file |
|---|---|
| Linux / macOS | `~/.ssh/config` |
| Windows | `C:\Users\<you>\.ssh\config` (`%USERPROFILE%\.ssh\config`; no file extension, see below) |
| WSL | `~/.ssh/config` *inside* WSL; WSL has its own, separate from Windows' |

The file may not exist yet; create it. Add:

```
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    AddKeysToAgent yes
    # macOS only: also keep the passphrase in the macOS keychain
    #UseKeychain yes
    # Networks that block port 22 (ssh -T hangs or times out): remove the # from these two lines
    #Hostname ssh.github.com
    #Port 443
```

- `User git`: GitHub's SSH user name is always `git` (it is the `git@` in the addresses).
- `IdentityFile` names the private key; `~` stands for your home directory
  (`C:\Users\<you>` on Windows; if Windows ssh reports that it cannot find the file,
  write the path out: `IdentityFile C:/Users/<you>/.ssh/id_ed25519`).
- `IdentitiesOnly yes` offers only that key. Without it, ssh also offers every key your
  agent holds, one after the other, and a server may hang up with "Too many authentication
  failures" before the right one is tried.
- `AddKeysToAgent yes` adds the key to a running agent the first time it is used.
- `UseKeychain yes` is an Apple extension; other systems reject it with "Bad
  configuration option", so uncomment it on macOS only.
- Port 443: GitHub also accepts SSH connections on port 443 at the host name
  `ssh.github.com`, for networks that block port 22
  ([GitHub's instructions](https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port)).
  Addresses of the form `git@github.com:...` keep working, because the entry is matched by
  the name `github.com` in the address. The first connection through port 443 asks about
  the host key again: compare the fingerprint with GitHub's list as in section 2.

Check what ssh will use with `ssh -G github.com | grep -iE "^(hostname|port|user|identityfile)"`
(on Windows PowerShell: `ssh -G github.com | Select-String "^(hostname|port|user|identityfile)"`),
then repeat `ssh -T git@github.com`.

**Windows: Notepad silently saves `config` as `config.txt`**, and OpenSSH then ignores
it. The safest way is to open the exact path from PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
notepad "$env:USERPROFILE\.ssh\config"
```

If you already have a `config.txt`, rename it:
`Rename-Item "$env:USERPROFILE\.ssh\config.txt" config`.

### The SSH agent

The **agent** is a background program that holds your unlocked keys in memory, so that
you type the passphrase once per login session instead of for every `git push`.
`AddKeysToAgent` and, on Perlmutter, key forwarding
([Perlmutter page 2](perlmutter/02-shell-setup.md#1-github-from-perlmutter)) need one running.

- **macOS and most Linux desktops** start one at login. `ssh-add -l` lists the loaded
  keys; "The agent has no identities." is fine, and "Could not open a connection to your
  authentication agent" means none is running. Start one for the current terminal with
  `eval "$(ssh-agent -s)"`.
- **Windows** has the service but disabled by default. Once, in an *administrator*
  PowerShell:

  ```powershell
  Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent
  ```

With the config entry, the `ssh -T git@github.com` test (or the first `git pull`) asks
for the passphrase and loads the key. To load it by hand:

```bash
ssh-add ~/.ssh/id_ed25519            # Linux; macOS: ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

```powershell
ssh-add $env:USERPROFILE\.ssh\id_ed25519      # Windows
```

## 4. git, once

On every machine where you use git (your laptop, and Perlmutter):

```bash
git config --global user.name "Your Name"
git config --global user.email "<the email on your GitHub account>"
git config --global pull.rebase true        # keep history linear when pulling
git config --global init.defaultBranch main
```

`user.name` and `user.email` are written into every commit you make.
