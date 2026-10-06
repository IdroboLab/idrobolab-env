# 1. Account and login

From no account to `ssh perlmutter` on your laptop (Windows, macOS or Linux). Do the
steps in order. All of them are one-time except step 3, which you repeat every day.

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
key without asking again. Download it
from <https://portal.nersc.gov/cfs/mfa/> (file names carry the version, 2.1.x at the
time of writing):

| OS | File | Install |
|---|---|---|
| Windows 10/11 | `sshproxy-<version>-windows-universal.msixbundle` | Double-click, **Install**, untick "Launch when ready". Then use it from PowerShell or Command Prompt. |
| macOS | `sshproxy-<version>-macos-universal.pkg` | Double-click; it installs to `/usr/local/bin`. If macOS blocks it: System Settings → Privacy & Security → **Open Anyway**. |
| Linux (x86_64) | `sshproxy-<version>-linux-x86_64.tar.gz` | See below. Use the `-musl` file if the normal one complains about glibc; `aarch64` for ARM machines. |

```bash
# Linux: the tarball holds a single executable called sshproxy
tar xzf sshproxy-*-linux-x86_64.tar.gz
mkdir -p ~/.ssh ~/.local/bin && mv sshproxy ~/.local/bin/
sshproxy --help        # if "command not found": add ~/.local/bin to PATH
```

Windows needs its built-in OpenSSH client (standard on Windows 10 1809+ and 11):
`ssh -V` in PowerShell should print a version.

## 3. Get today's key (every day)

```bash
sshproxy -u <username>        # asks for password+OTP
```

This writes `~/.ssh/nersc` and `~/.ssh/nersc-cert.pub` (on Windows
`C:\Users\<you>\.ssh\nersc`), valid for 24 hours. When `ssh perlmutter` starts
asking for a password again, the key has expired: run `sshproxy` again.

## 4. SSH config

Add these two entries to your **local** SSH config, with your NERSC username:

| OS | File |
|---|---|
| Linux / macOS | `~/.ssh/config` |
| Windows | `C:\Users\<you>\.ssh\config` (no file extension; see below) |
| WSL | `~/.ssh/config` *inside* WSL; WSL has its own, separate from Windows' |

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

- `~/.ssh/nersc` works as written on all three systems, Windows included.
- `IdentitiesOnly yes` offers only the NERSC key. Without it, ssh also tries every
  other key you have, and NERSC may disconnect you with "Too many authentication
  failures".
- `ForwardAgent yes` lets git on Perlmutter use the GitHub key on your laptop
  ([page 2](02-github.md#3-github-from-perlmutter)).
- `ServerAliveInterval` keeps an idle connection from being dropped.
- Listing the full hostname on the `Host` line means `ssh perlmutter.nersc.gov`
  gets the same settings as `ssh perlmutter`.
- X11 forwarding (`ForwardX11`) is left out on purpose: use ThinLinc for graphical
  programs ([page 9](09-thinlinc-nionswift.md)). For an occasional X window, use
  `ssh -Y perlmutter`. On Windows this also needs a local X server.
- `nersc-dtn` is for file transfers ([page 4](04-storage-and-transfer.md)).

**Windows: Notepad silently saves `config` as `config.txt`**, and OpenSSH then ignores
it. The safest way is to open the exact path from PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
notepad "$env:USERPROFILE\.ssh\config"
```

If you already have a `config.txt`, rename it:
`Rename-Item "$env:USERPROFILE\.ssh\config.txt" config`.

## 5. Log in

```bash
ssh perlmutter
```

On the first connection, ssh shows the server's key fingerprint. Compare it with the
fingerprints NERSC publishes at <https://docs.nersc.gov/connect/> before you type
`yes`. You land on a **login node**: a machine shared with every other user. Use it
to edit, submit and run short tests, and do the real work on compute nodes
([page 5](05-jobs.md)).

## 6. VS Code (optional)

The **Remote - SSH** extension works with the `perlmutter` alias from §4. It runs a
server process on the login node, so close the remote window when you are done. Like
ssh, it stops connecting once the day's key expires.
