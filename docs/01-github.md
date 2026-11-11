# 1. GitHub: account and SSH key

The group keeps its settings, job templates and these pages in **git** repositories on
**GitHub**. git records the history of a folder of files: every saved state (a *commit*)
can be compared with, or restored from, any other, and several people can work on the same
files without overwriting each other. GitHub hosts the shared copy of such a folder (a
*repository*) and is where changes are reviewed. The group repository is
**[IdroboLab/idrobolab-env](https://github.com/IdroboLab/idrobolab-env)**; your own
analysis code belongs in git too ([general page 2](02-cloning.md#5-your-own-projects-and-your-data)).

This page sets up what every later page assumes: a GitHub account, membership of the
IdroboLab organisation, an SSH key that lets git on your laptop identify you (with the
config entry that goes with it), and git's one-time settings. Cloning repositories is the
next page ([general page 2](02-cloning.md)); getting the same access on Perlmutter is in
[Perlmutter page 2](perlmutter/02-shell-setup.md#1-github-from-perlmutter).

## Your terminal on the laptop

Every command in these pages marked "on your laptop" runs in a terminal. Where the
instructions differ by operating system, there is a subsection for each. A command that
is the same everywhere is given once, in a single unlabelled block, and works unchanged
in Command Prompt, PowerShell, Terminal and a Linux terminal.

### Windows

Windows has two command-line shells, **Command Prompt** (`cmd.exe`) and **PowerShell**.
Either works for everything these pages ask of your laptop. Open one from the Start menu
(type `cmd` or `powershell`; NERSC gives the same tip: type either in the taskbar search
box), or open **Windows Terminal**, which hosts both in tabs
([Microsoft](https://learn.microsoft.com/en-us/windows/terminal/)). The prompt tells them
apart: `C:\Users\you>` is Command Prompt, `PS C:\Users\you>` is PowerShell.

The built-in **OpenSSH client** (`ssh`, `scp`, `ssh-keygen`, `ssh-add`) runs in both
shells. Check with `ssh -V`, which prints a version. If Windows does not know the command,
add the client: Start menu → type *Optional Features* → add **OpenSSH Client**, or, in an
*administrator* PowerShell,
`Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0`
([Microsoft](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)).

Where a command differs between the two shells, the pages give one block labelled
**Command Prompt** and one labelled **PowerShell**; a single block means the command is
the same in both. The difference you meet most is how to write your home folder:
`%USERPROFILE%` in Command Prompt, `$env:USERPROFILE` in PowerShell (both mean
`C:\Users\<you>`). Command Prompt does not expand `~`, and Windows PowerShell 5.1 passes
it to programs as it is (PowerShell 7 can expand it, but do not rely on that): in
commands, write `%USERPROFILE%` or `$env:USERPROFILE`. Only ssh itself understands
`~/.ssh/...` inside its config file.

You can instead use the Windows Subsystem for Linux (WSL), a Linux terminal inside
Windows. It has its own home folder and its own `~/.ssh`, separate from Windows': if you
choose it, follow the Linux instructions inside WSL throughout, and do not mix the two
(for example, the `sshproxy` you install on Windows does not put a key into WSL). The
pages assume native Windows.

### macOS

Open **Terminal**: click Spotlight in the menu bar, type *Terminal* and click it, or open
`/Applications/Utilities` in Finder and double-click Terminal
([Apple](https://support.apple.com/guide/terminal/open-or-quit-terminal-apd5265185d-f365-44cb-8b09-71a064a42125/mac)).
`ssh`, `scp`, `ssh-keygen` and `ssh-add` come with macOS.

### Linux

Open the terminal program of your desktop. `ssh -V` shows whether the OpenSSH client is
installed; if not, install your distribution's OpenSSH client package.

## 1. Account and the IdroboLab organisation

1. Create an account at <https://github.com> (or use the one you have).
2. Turn on two-factor authentication: profile picture → **Settings** → **Password and
   authentication** → **Enable two-factor authentication**. Scan the QR code with an
   authenticator app, enter the six-digit code, and store the recovery codes somewhere safe:
   they get you back into your account if you lose the phone.
3. Send an admin your GitHub username. They add you to the **IdroboLab** organisation, and with
   it to `idrobolab-env`, which is private. GitHub emails you an invitation with a link;
   click it to accept.

## 2. An SSH key for GitHub

git talks to GitHub over SSH with a key pair: the **private key** stays on your machine
and is never shared, and the **public key** (the file ending in `.pub`) is registered on
GitHub. This is a different key from the 24-hour NERSC key from `sshproxy`.

**Create the key on your laptop:**

```bash
ssh-keygen -t ed25519 -C "<your email>"
```

Press Enter to accept the default file name, and choose a passphrase. This writes the
private key `id_ed25519` and the public key `id_ed25519.pub` into the `.ssh` folder of
your home folder: `~/.ssh/` on macOS and Linux, `C:\Users\<you>\.ssh\` on Windows.

**Register the public key** on GitHub: profile picture → **Settings** → **SSH and GPG
keys** → **New SSH key**. Give it a title such as "laptop", leave the key type at
**Authentication Key**, and paste the contents of the `.pub` file into **Key**, without
adding newlines or spaces ([GitHub](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)).
Show the file, or copy it to the clipboard:

### Windows

Command Prompt:

```
type "%USERPROFILE%\.ssh\id_ed25519.pub"
clip < "%USERPROFILE%\.ssh\id_ed25519.pub"
```

PowerShell:

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | clip
```

The first line of each pair prints the key; the second copies it to the clipboard
(`type` is also an alias of `Get-Content` in PowerShell).

### macOS

```bash
cat ~/.ssh/id_ed25519.pub              # print it
pbcopy < ~/.ssh/id_ed25519.pub         # or copy it to the clipboard
```

### Linux

```bash
cat ~/.ssh/id_ed25519.pub
```

Select the printed line in the terminal and copy it.

### Test it

```bash
ssh -T git@github.com
```

The first time, ssh shows GitHub's host key fingerprint
and asks whether to continue. Compare it with the fingerprints GitHub publishes at
<https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints>
(the Ed25519 one starts `SHA256:+DiY3wvv`), then type `yes`. The answer
"Hi <username>! You've successfully authenticated, but GitHub does not provide shell
access." means it works.

### Tokens instead of keys

GitHub also accepts HTTPS with a personal access token
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

### Create the file

The file may not exist yet; create it.

#### Windows

**Notepad silently saves `config` as `config.txt`**, and OpenSSH then ignores it. The
safest way is to open the exact path from the shell: Notepad offers to create the file
under that name.

Command Prompt:

```
mkdir "%USERPROFILE%\.ssh"
notepad "%USERPROFILE%\.ssh\config"
```

PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
notepad "$env:USERPROFILE\.ssh\config"
```

(`ssh-keygen` has made the `.ssh` folder already; if `mkdir` says it exists, go on.) If
you already have a `config.txt`, rename it:

Command Prompt:

```
ren "%USERPROFILE%\.ssh\config.txt" config
```

PowerShell:

```powershell
Rename-Item "$env:USERPROFILE\.ssh\config.txt" config
```

#### macOS

Create or edit `~/.ssh/config` with any text editor, for example `nano ~/.ssh/config`.

#### Linux

Same as macOS: create or edit `~/.ssh/config` with any text editor, for example
`nano ~/.ssh/config`.

### The entry

Add:

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

The lines mean:

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

### Check the entry

See what ssh will use for `github.com` (the four lines shown are `hostname`, `port`,
`user` and `identityfile`), then repeat `ssh -T git@github.com`.

#### Windows

Command Prompt:

```
ssh -G github.com | findstr /b /i /c:"hostname " /c:"port " /c:"user " /c:"identityfile "
```

PowerShell:

```powershell
ssh -G github.com | Select-String "^(hostname|port|user|identityfile) "
```

#### macOS

```bash
ssh -G github.com | grep -iE "^(hostname|port|user|identityfile) "
```

#### Linux

Same as macOS:

```bash
ssh -G github.com | grep -iE "^(hostname|port|user|identityfile) "
```

### The SSH agent

The **agent** is a background program that holds your unlocked keys in memory, so that
you type the passphrase once per login session instead of for every `git push`.
`AddKeysToAgent` and, on Perlmutter, key forwarding
([Perlmutter page 2](perlmutter/02-shell-setup.md#1-github-from-perlmutter)) need one running.
With the config entry, the `ssh -T git@github.com` test asks for the passphrase and loads
the key (so does the first `git pull`, on Windows once git uses Windows' own ssh, see
[section 4](#4-git-once)); the commands below load it by hand.

#### Windows

Windows has the agent as a service, but it is disabled by default. Enable it once, in an
*administrator* shell (right-click Command Prompt or PowerShell → **Run as
administrator**; GitHub and Microsoft both name an elevated PowerShell for this step).

PowerShell:

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent
```

Command Prompt (this runs the same PowerShell commands):

```
powershell -Command "Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent"
```

Then load the key in an ordinary (non-administrator) window, and list what the agent
holds:

Command Prompt:

```
ssh-add "%USERPROFILE%\.ssh\id_ed25519"
ssh-add -l
```

PowerShell:

```powershell
ssh-add $env:USERPROFILE\.ssh\id_ed25519
ssh-add -l
```

([GitHub](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent),
[Microsoft](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement).)

#### macOS

macOS starts an agent at login. `ssh-add -l` lists the loaded keys; "The agent has no
identities." is fine. To load the key and keep its passphrase in the macOS keychain
(with `UseKeychain yes` uncommented in the config entry):

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Use the `ssh-add` that comes with macOS, not one installed by Homebrew or MacPorts
([GitHub](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)).

#### Linux

Most Linux desktops start an agent at login. `ssh-add -l` lists the loaded keys; "The
agent has no identities." is fine, and "Could not open a connection to your
authentication agent" means none is running. Start one for the current terminal, then
load the key:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

## 4. git, once

### Install git on your laptop

Perlmutter has git already. Check your laptop with `git --version`. If it is missing
([git-scm.com](https://git-scm.com/install/)):

#### Windows

Download and run the installer from <https://git-scm.com/download/win>, or, in either
shell, `winget install Git.Git`. Then open a **new** Command Prompt or PowerShell window
and run `git --version`; if the shell does not know `git`, run the installer again and
choose the option that puts git on the `PATH`. Then do the one extra setting under
[Git for Windows and the ssh agent](#git-for-windows-and-the-ssh-agent) below.

#### macOS

Run `git --version`: if git is missing, macOS offers to install the Xcode Command Line
Tools, which include it (`xcode-select --install` does the same;
[Pro Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)). Or, with
Homebrew, `brew install git`.

#### Linux

```bash
sudo apt update && sudo apt install git     # Debian, Ubuntu
sudo dnf install git                        # Fedora
sudo pacman -S git                          # Arch
```

### Its settings

On every machine where you use git (your laptop, and Perlmutter) run these once:

```bash
git config --global user.name "Your Name"
git config --global user.email "<your address>"
git config --global pull.rebase true        # keep history linear when pulling
git config --global init.defaultBranch main
```

`user.name` and `user.email` are written into every commit you make; for the address, read the next section first.

### Keeping your address out of public commits

Everyone who can see a repository can read the address in its commits. GitHub gives each account a noreply address for this, `<id>+<username>@users.noreply.github.com`, shown under Settings > Emails once "Keep my email addresses private" is ticked; commits made with it still count as yours. On Perlmutter and Delta the setup script sets it for you:

```bash
~/idrobolab-env/perlmutter/helpers/setup-user.sh --github-email <id>+<username>@users.noreply.github.com
```

(`delta/helpers/setup-user.sh` on Delta.) It writes the address to `~/.gitconfig-github` and three `includeIf` entries to your global git config, so that repositories with a `github.com` remote commit with it and every other repository (GitLab, Overleaf) keeps your global `user.email`. This needs git 2.36 or newer, and it matches the remote addresses `https://github.com/...`, `git@github.com:...` and `ssh://git@github.com/...`; a remote written another way (`https://<user>@github.com/...`) keeps the global address. A `user.email` you set in the global config afterwards can override the rule. Run without the option, the script asks git which address a commit in a GitHub repository would carry, reports it, and warns when it is not a noreply address or not the one you set; `--undo` removes the three entries. On a laptop, set the same three entries by hand or use the noreply address as your global `user.email`.

### Git for Windows and the ssh agent

On Windows only. Git for Windows comes with its own `ssh.exe`, which cannot talk to the
Windows ssh agent enabled in section 3, so git would ask for your passphrase on every
`git pull` and `git push` even though the key is loaded. Tell git to use Windows' own
ssh once ([GitHub](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent),
section "Troubleshooting SSH agent conflicts in Windows"):

```
git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"
```

Alternatively, choose "Use external OpenSSH" when you run the Git for Windows installer.
