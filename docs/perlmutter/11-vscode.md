# 11. VS Code

VS Code's **Remote - SSH** extension opens a folder on Perlmutter in the VS Code on your
laptop: the editor, file explorer, terminals, git and extensions all work on Perlmutter's
files, while the window stays on your laptop. It uses your `sshproxy` key and the SSH
config from [page 1](01-login.md), so do pages 1 and 4 first. NERSC's own page is
<https://docs.nersc.gov/connect/vscode/>.

VS Code can connect to a **login node** (for editing, git and short tests) or to a
**compute node** you have booked with `salloc` (for real work and GPUs). The same rules
apply as on the command line ([page 4](04-jobs.md#login-nodes-vs-compute-nodes)).

## 1. Install

1. Install VS Code from <https://code.visualstudio.com>.
2. In the Extensions view (`Ctrl+Shift+X`, on macOS `Cmd+Shift+X`), install
   **Remote - SSH** (by Microsoft, `ms-vscode-remote.remote-ssh`).

The extension uses your laptop's OpenSSH client and its `~/.ssh/config`. Nothing else
needs setting up for a login node.

## 2. Connect to a login node

1. Get today's key: `sshproxy -u <username>`
   ([page 1](01-login.md#3-get-todays-key-every-day)), and check that `ssh perlmutter`
   works in a terminal. VS Code connects the same way.
2. In VS Code, open the Command Palette (`F1`, or `Ctrl+Shift+P` / `Cmd+Shift+P`), run
   **Remote-SSH: Connect to Host…** and pick `perlmutter`. If asked for the platform,
   choose **Linux**.
3. The first connection installs the VS Code server into `~/.vscode-server` on
   Perlmutter, which takes a minute.
4. **File → Open Folder…** and open one project folder, for example `~/idrobolab-env`.
   To see your home directory, the project tree and `$SCRATCH` in one window instead, use
   the optional workspace file ([§4](#4-one-window-for-home-projects-and-scratch)).

The login node is shared with every other user, and the VS Code server and every
extension you install on Perlmutter run on it. So:

- **Open one project folder, or the workspace file (§4); never your home directory or
  `/global/cfs/cdirs/<project>` as a bare folder.** VS Code watches and searches every file
  under a folder you open. The workspace file lists both, with watching turned off for the
  CFS tree and `$SCRATCH` and for the cache folders in your home directory.
- **Run computations on a compute node** (§3), not in the VS Code terminal on a login
  node.
- **Close the remote window when you are done** (File → Close Remote Connection), rather
  than leaving it open overnight.

An open window keeps working after the day's key expires; a new connection, or a
reconnect after a dropped network, needs a fresh `sshproxy` key.

### Home quota

The VS Code server, and the extensions you install on Perlmutter, live in
`~/.vscode-server`, in your home directory (40 GB and 1 million files,
[page 3](03-storage-and-transfer.md)). **If your home directory is over its quota, VS Code
cannot connect.** Check with `showquota` and `du -sh ~/.vscode-server` from a normal
`ssh perlmutter`. After closing every VS Code window connected to Perlmutter, deleting
`~/.vscode-server` is safe: VS Code installs the server again on the next connection,
and you reinstall the extensions (and redo the settings) you used on Perlmutter.

## 3. Connect to a compute node

For GPUs, or anything heavier than editing, book a node with `salloc` and point VS Code
at it.

### One-time: SSH config

Add this entry to your **local** SSH config, below the `perlmutter` entry from
[page 1, §4](01-login.md#4-ssh-config), with your NERSC username:

```
Host nid??????
    User                   <username>
    IdentityFile           ~/.ssh/nersc
    IdentitiesOnly         yes
    ProxyJump              perlmutter
    StrictHostKeyChecking  no
    LogLevel               QUIET
```

- `nid??????` matches the compute nodes' names: `nid` and six digits, such as `nid200021`.
- `ProxyJump perlmutter`: compute nodes can only be reached from inside NERSC, so ssh
  goes through a login node, using the `perlmutter` entry.
- `StrictHostKeyChecking no` and `LogLevel QUIET` are NERSC's settings. You get a
  different node each time: the first setting accepts each new node's host key instead
  of asking, the second hides the messages about it. The login node you go through is
  still checked as usual.
- No `ForwardAgent`: as [page 2](02-shell-setup.md#1-github-from-perlmutter) says, git
  that needs your GitHub key (`pull`, `push`) runs on a login node. Use a login-node
  window or `ssh perlmutter` for that.
- On Windows, `~/.ssh/nersc` works as on page 1; use the full path
  `C:\Users\<you>\.ssh\nersc` if ssh says it cannot find the key.

### One-time: two VS Code settings

Open the Command Palette, run **Preferences: Open User Settings (JSON)** and add these two
lines inside the outer `{ }`:

```json
"remote.SSH.maxReconnectionAttempts": 2,
"remote.SSH.useFlock": false,
```

- `maxReconnectionAttempts`: when your allocation ends, the node is gone. VS Code then
  gives up after two attempts instead of retrying for a long time.
- `useFlock: false`: VS Code takes a lock with `flock` when it installs or starts its
  server, and `flock` does not work on `$HOME` as compute nodes mount it. NERSC asks for
  this setting. It applies to every host you connect to, which does no harm.

### Every time

1. In a terminal on your laptop, log in and book a node, with an `salloc` line from
   [page 4](04-jobs.md#interactive-sessions-salloc). For 1 GPU for an hour:

   ```bash
   ssh perlmutter
   salloc -C gpu -q shared_interactive -A "$NERSC_PROJECT" -t 01:00:00 -n 1 -c 32 --gpus-per-task=1
   ```

   When the session starts, `salloc` prints the node (`salloc: Nodes nid200021 are
   ready for job`), and `hostname` in the new shell prints it too.
2. In VS Code, run **Remote-SSH: Connect to Host…** and type the node name, for example
   `nid200021` (it is not in the list), then press Enter.
3. **Leave the `salloc` terminal open.** The allocation ends when its time runs out,
   when you type `exit` in that shell, or when that terminal's connection drops (a
   closed lid, a lost network), and the VS Code window then disconnects. Type `exit` as
   soon as you are done: the job is charged until it ends, whether you use it or not.

**Run programs in the `salloc` terminal**, with `srun` as on [page 4](04-jobs.md), and
start the group container there as on [page 6](06-containers.md). Use the VS Code
window for editing and browsing files. A terminal inside the VS Code window is a plain
ssh shell on the node, not part of the `salloc` session: the `SLURM_*` variables are not
set there, so `srun`, or a helper such as `interactive_gpu_shared.sh`, would ask Slurm
for a second allocation, charged on top of the first.

## 4. One window for home, projects and scratch

This is optional. Write the workspace file once, on a login node:

```bash
~/idrobolab-env/perlmutter/helpers/setup-user.sh --vscode-workspace
```

It creates `~/perlmutter.code-workspace`, a workspace file that shows three folders in
one window: your home directory, `/global/cfs/cdirs/<project>` (the whole project tree) and
`$SCRATCH`. The setup script ([page 2](02-shell-setup.md#4-group-environment)) never
replaces an existing file. Open the file with **File → Open Workspace from File…**
instead of **Open Folder…**; VS Code remembers it under **File → Open Recent**.

To change the folders, for example to add a folder outside these three, rewrite the file
with the folders you want added:

```bash
~/idrobolab-env/perlmutter/helpers/make-vscode-workspace.sh /path/to/folder
```

It always writes home first, then the project tree, then the folders you name, then
`$SCRATCH`. Edits you make to the file by hand stay until you run the script above.

- **Why home comes first.** The Claude Code extension takes its working directory, its
  memory and its list of past sessions from the **first** folder of the window. Every
  window opened from this file therefore shows the same sessions, and a window opened on
  a bare project folder shows that folder's own, different list. Sessions you start with
  `claude` in a terminal belong to the folder you started them in: start them in `~` to
  see them in the window too.
- **What it turns off.** The file tells VS Code not to watch the project tree, any folder
  you add and `$SCRATCH` (they are large, shared filesystems), and not to watch folders
  named `.cache`, `.local`, `.conda`, `.cupy`, `.nv`, `.venv`, `node_modules` and
  `__pycache__` (inside projects too), nor `~/.vscode-server`, and not to follow symlinks
  when searching. The consequence: the explorer may not pick up files created by jobs on
  its own, so use its refresh button.
- **What it does not turn off.** Find in Files and Quick Open (`Ctrl+P`) walk every
  folder of the window when you use them, and so can extensions that index the workspace.
  On the project tree or `$SCRATCH` that is slow and loads the login node: search inside
  a subfolder (right-click it → **Find in Folder…**) instead.

## 5. Python and coding agents in VS Code

- **Your own environments:** with the Python extension installed on Perlmutter, run
  **Python: Select Interpreter** and pick a uv environment from
  [page 5](05-python-uv.md). A `.venv` inside the opened folder is offered
  automatically; for one elsewhere, such as `~/venvs/analysis`, give the full path to its
  `bin/python` (`echo ~/venvs/analysis/bin/python` prints it).
- **The group container:** its Python is inside the image ([page 6](06-containers.md)),
  where the Python extension does not see it. Run it in the `salloc` terminal (§3), or
  use a container kernel in Jupyter ([page 8](08-jupyter.md)).
- **Coding agents** (Claude Code, Codex, also as VS Code extensions): set them up as on
  [page 10](10-coding-agents.md) first. The rules there apply however you start them.

## 6. When it does not connect

One row per symptom, with its usual cause and the fix.

| Symptom | Cause and fix |
|---|---|
| Asks for a password, or "Permission denied" | today's key has expired: run `sshproxy -u <username>` |
| "Permission denied" on a `nid…` host, though `ssh perlmutter` works | no job of yours runs on that node: the job has ended, or the name is wrong. Check `squeue --me` |
| A `nid…` name is not found | a typo in the node name |
| Fails while setting up the VS Code server, though `ssh perlmutter` works | home directory over quota: see [Home quota](#home-quota) |
| "Too many authentication failures" | `IdentitiesOnly yes` is missing from the SSH config entry |
