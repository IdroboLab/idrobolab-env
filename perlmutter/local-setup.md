# Local setup: connecting to Perlmutter from your own machine

One-time setup for reaching Perlmutter from a laptop/workstation (Windows, macOS, or
Linux): SSH config, MFA (`sshproxy`), and how to log in and move files.

## 1. SSH config

Add two `Host` entries to your **local** `~/.ssh/config` (create the file if it
doesn't exist yet — see §3 for Windows, where creating a plain-text file with no
extension needs an extra step). Config file location by OS:

| OS | `.ssh` directory | Full path to `config` |
|---|---|---|
| Linux | `~/.ssh/` | `/home/<username>/.ssh/config` |
| macOS | `~/.ssh/` | `/Users/<username>/.ssh/config` |
| Windows (OpenSSH — built into Win10 1809+/Win11, also used by Git Bash, PowerShell, VS Code Remote-SSH) | `%USERPROFILE%\.ssh\` | `C:\Users\<username>\.ssh\config` |

If you use WSL, its OpenSSH client is a separate Linux install with its own
`~/.ssh/config` inside the WSL filesystem — the Windows-native path above doesn't
apply there.

Template (replace `<USERNAME>` with your NERSC username; `~` in `IdentityFile`
resolves correctly on all three OSes' OpenSSH clients, so the path below doesn't need
to change per OS):

```
Host perlmutter
    HostName             perlmutter.nersc.gov
    User                 <USERNAME>
    IdentityFile          ~/.ssh/nersc
    ServerAliveInterval   240
    ForwardAgent          yes
    ForwardX11            yes
    AddKeysToAgent        yes

Host nersc-dtn
    HostName              dtn.nersc.gov
    User                  <USERNAME>
    IdentityFile          ~/.ssh/nersc
    ServerAliveInterval   240
    ForwardAgent          yes
    ForwardX11            yes
    AddKeysToAgent        yes
```

`~/.ssh/nersc` is the default key path `sshproxy` writes to (§2) — if you point
`sshproxy` somewhere else, update `IdentityFile` to match.

## 2. MFA: sshproxy

NERSC requires MFA-backed short-lived SSH keys, not a password or a long-lived key.
Install/download `sshproxy` and read the setup instructions at
https://portal.nersc.gov/cfs/mfa/ — that page covers your specific OS and the
one-time enrollment (registering your MFA device with your NERSC account).

Once installed, generate a key:

```
sshproxy -u <USERNAME>
```

This writes a key pair (default `~/.ssh/nersc` / `~/.ssh/nersc-cert.pub`) valid for
**24 hours**. Re-run it once a day (or whenever `ssh perlmutter` starts rejecting the
key) — there's no way to extend an existing key's lifetime, only issue a new one.

## 3. Windows only: creating `.ssh\config` in Notepad

Notepad's *Save As* dialog silently appends `.txt` to whatever filename you type,
so saving as `config` actually produces `config.txt` — and OpenSSH will not find a
config file under that name. Two ways to avoid it:

- **Quote the filename**: in the *File name* field, type `"config"` — including the
  quote marks. Notepad treats a quoted name as literal and skips the `.txt` append,
  regardless of the *Save as type* filter.
- **Change the type filter**: in the *Save as type* dropdown, switch from
  *Text Documents (*.txt)* to *All Files (*.*)*, then type `config` without quotes.
- Either way, make sure you're saving into the `.ssh` folder (create it first if it
  doesn't exist — see below), not e.g. `Documents`.

If you already saved it as `config.txt`, rename it from the command line instead of
fighting Notepad's dialog again — File Explorer also hides the `.txt` extension by
default, which makes it easy to rename to `config.txt.txt` by mistake:

```powershell
# PowerShell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
Rename-Item "$env:USERPROFILE\.ssh\config.txt" "config"
```

```cmd
:: Command Prompt
mkdir "%USERPROFILE%\.ssh"
ren "%USERPROFILE%\.ssh\config.txt" config
```

A third option that sidesteps the whole *Save As* dialog: open Notepad directly on
the target path from a terminal. If the file doesn't exist yet, Notepad offers to
create it; typing `Ctrl+S` afterward writes straight to that exact path, no
extension added.

```powershell
notepad "$env:USERPROFILE\.ssh\config"
```

(Any plain-text editor works the same way, including without the `.txt` quirk —
e.g. Notepad++ or VS Code — if Notepad is inconvenient.)

## 4. Logging in and copying files

Log in to a login node:

```
ssh perlmutter
```

**For file transfers, always use the `nersc-dtn` alias — never `perlmutter` — even
though the login node accepts `scp`/`rsync` too.** NERSC's Data Transfer Nodes
(`dtn.nersc.gov`) are provisioned specifically for bulk I/O: dedicated network
bandwidth to the WAN and to NERSC's filesystems, and no interactive-process limits.
Login nodes are a shared interactive resource sized for compiling, editing, and job
submission across many simultaneous users; NERSC's login-node abuse policy kills
long-running or resource-heavy processes there on sight, and a large transfer is
exactly the kind of process that gets caught by it — plus it competes with everyone
else's interactive session in the meantime, while a DTN transfer doesn't.

```bash
# copy a local directory to your $SCRATCH on Perlmutter
rsync -azPv mydata/ nersc-dtn:/pscratch/sd/<u>/<USERNAME>/mydata/

# copy a single file
scp mydata.tar.gz nersc-dtn:/pscratch/sd/<u>/<USERNAME>/

# pull results back down (same alias, reversed direction)
rsync -azPv nersc-dtn:/pscratch/sd/<u>/<USERNAME>/results/ ./results/
```

(`-azPv`: archive mode, compress in transit, keep partials and show progress,
verbose — reasonable defaults for both directions; add `--exclude`/`--dry-run` etc.
as a given transfer needs.)
