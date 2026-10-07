# 1. Account and login

From no account to `ssh perlmutter` on your laptop (Windows, macOS or Linux). Do the
steps in order. All of them are one-time except step 3, which you repeat every day.
Where the instructions differ by system, there is a subsection each for Windows (Command
Prompt and PowerShell), macOS and Linux. How to open a terminal, and the OpenSSH client
that Windows needs, are described in the
[GitHub page](../01-github.md#your-terminal-on-the-laptop).

## 1. NERSC account and MFA

1. **Account.** Request a NERSC account for project **<project>** (see
   <https://docs.nersc.gov/accounts/>). The PI or a PI proxy approves it in Iris. Until
   you are in <project>, you cannot reach the group's files or charge jobs.
2. **MFA token.** Log in to <https://iris.nersc.gov>, open the **MFA** tab, enter a
   description and click **+ Add Token**. Scan the QR code with an authenticator app
   (Google Authenticator, Authy, 1Password, …), then click **Test**. Write down the
   token ID; NERSC support asks for it if you lose the phone.

From now on, "password+OTP" means your NERSC password **immediately followed by** the
6-digit code from the app, with no space.

## 2. Install `sshproxy`

NERSC asks for MFA on every SSH login. You can type password+OTP each time, but
`sshproxy` is far more convenient: it trades one password+OTP for an SSH key that is
valid for **24 hours**, and every ssh, scp, rsync and ThinLinc login that day uses the
key without asking again. Download it from <https://portal.nersc.gov/cfs/mfa/> (file
names carry the version, 2.1.x at the time of writing); NERSC's description is on its
[MFA page](https://docs.nersc.gov/connect/mfa/).

### Windows

Download `sshproxy-<version>-windows-universal.msixbundle` (Windows 10/11, x86-64 and
ARM). Double-click it and click **Install**; untick "Launch when ready", because the
program is meant to be run on the command line. Then use it from Command Prompt or
PowerShell. It also needs the built-in OpenSSH client (`ssh -V` should print a version;
[the GitHub page](../01-github.md#your-terminal-on-the-laptop) says what to do if not).

Check the install in a **new** window:

```
sshproxy --version
```

If the shell does not know `sshproxy`, see where Windows put it: `where sshproxy` in
Command Prompt, `Get-Command sshproxy` in PowerShell.

With WSL, NERSC says to install a Linux executable inside WSL instead (as under Linux
below); the key then lives in WSL's own `~/.ssh`, not in Windows'. The ThinLinc client
([page 9](09-thinlinc-nionswift.md)) needs the Windows one.

### macOS

Download `sshproxy-<version>-macos-universal.pkg` (Apple and Intel). Double-click it; it
installs to `/usr/local/bin`. If macOS blocks it ("can't be opened because it was not
downloaded from the App Store"): System Settings → Privacy & Security → **Open Anyway**.
Then, in Terminal, `sshproxy --version` should print a version.

### Linux

Download `sshproxy-<version>-linux-x86_64.tar.gz`. Use the `-musl` file if the normal one
complains about glibc; `aarch64` for ARM machines. The tarball holds a single executable
called `sshproxy`:

```bash
tar xzf sshproxy-*-linux-x86_64.tar.gz
mkdir -p ~/.ssh ~/.local/bin && mv sshproxy ~/.local/bin/
sshproxy --help        # if "command not found": add ~/.local/bin to PATH
```

## 3. Get today's key (every day)

```bash
sshproxy -u <username>        # asks for password+OTP
```

The command is the same in Command Prompt, PowerShell, Terminal and a Linux terminal. It
writes `~/.ssh/nersc` and `~/.ssh/nersc-cert.pub` (on Windows `C:\Users\<you>\.ssh\nersc`
and `nersc-cert.pub` there), valid for 24 hours. When `ssh perlmutter` starts asking for
a password again, the key has expired: run `sshproxy` again.

On Windows, NERSC says to create the `.ssh` folder first if it does not exist (the
GitHub page's `ssh-keygen` has normally made it already):

Command Prompt:

```
mkdir "%USERPROFILE%\.ssh"
```

PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
```

## 4. SSH config

Add these two entries to your **local** SSH config, with your NERSC username. It is the
file you may already have made for GitHub: where it lives on each OS, and how to create
it on Windows without Notepad turning it into `config.txt`, is described in
[the GitHub page](../01-github.md#3-the-ssh-config-entry-for-githubcom). Keep the
`Host github.com` entry from there; the entries below are separate and don't overlap.

```
Host perlmutter perlmutter.nersc.gov
    HostName             perlmutter.nersc.gov
    User                 <username>
    IdentityFile         ~/.ssh/nersc
    IdentitiesOnly       yes
    ForwardAgent         yes
    ServerAliveInterval  240

Host nersc-dtn dtn.nersc.gov
    HostName             dtn.nersc.gov
    User                 <username>
    IdentityFile         ~/.ssh/nersc
    IdentitiesOnly       yes
    ServerAliveInterval  240
```

- `~/.ssh/nersc` works as written on all three systems, Windows included. NERSC's own
  Windows example writes the full path instead (`IdentityFile C:\Users\<you>\.ssh\nersc`);
  use that form if ssh says it cannot find the key.
- `IdentitiesOnly yes` offers only the NERSC key. Without it, ssh also tries every
  other key you have, and NERSC may disconnect you with "Too many authentication
  failures".
- `ForwardAgent yes` lets git on Perlmutter use the GitHub key on your laptop
  ([page 2](02-shell-setup.md#1-github-from-perlmutter)).
- `ServerAliveInterval` keeps an idle connection from being dropped.
- Listing the full hostname on the `Host` line means `ssh perlmutter.nersc.gov`
  gets the same settings as `ssh perlmutter`.
- X11 forwarding (`ForwardX11`) is left out on purpose: use ThinLinc for graphical
  programs ([page 9](09-thinlinc-nionswift.md)). For an occasional X window, use
  `ssh -Y perlmutter`. On Windows this also needs a local X server.
- `nersc-dtn` is for file transfers ([page 3](03-storage-and-transfer.md)).

## 5. Log in

```bash
ssh perlmutter
```

On the first connection, ssh shows the server's key fingerprint. Compare it with the
fingerprints NERSC publishes at <https://docs.nersc.gov/connect/> before you type
`yes`. You land on a **login node**: a machine shared with every other user. Use it
to edit, submit and run short tests, and do the real work on compute nodes
([page 4](04-jobs.md)).

## 6. VS Code (optional)

The **Remote - SSH** extension works with the `perlmutter` alias from §4. It runs a
server process on the login node, so close the remote window when you are done. Like
ssh, it stops connecting once the day's key expires.
