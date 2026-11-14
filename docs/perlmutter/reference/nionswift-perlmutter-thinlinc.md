# Nion Swift on Perlmutter Compute Nodes via ThinLinc

Runbook for running the Nion Swift GUI on a Perlmutter compute node with the display
delivered through NERSC's ThinLinc service.

Written 2026-07. NERSC policies (QOS limits, walltimes, charging) change; verify
against https://docs.nersc.gov before relying on specific numbers.

---

## 1. Architecture

ThinLinc does **not** run on Perlmutter. It is a center-wide service on a separate
host (`thinlinc.nersc.gov`). The display chain is:

```
laptop  <-- ThinLinc protocol (compressed) -->  thinlinc.nersc.gov
        <-- X11 over ssh                   -->  Perlmutter login node
        <-- X11 via Slurm / ssh -X         -->  compute node (Nion Swift runs here)
```

Consequences:

- ThinLinc only compresses the WAN leg. Both hops inside NERSC are plain X11 over
  SSH. Latency there is sub-ms, so it works, but canvas-heavy redraws (large image
  panels) ship raw pixmaps — expect usable, not workstation-snappy, interactivity.
- The ThinLinc session survives client disconnects with application state intact.
  The Slurm job does **not** survive its walltime. Session lifetime = job walltime.
- This is the same pattern NERSC documents for DDT, TotalView, and Mathematica,
  i.e. a supported workflow, not a hack.

## 2. Prerequisites

- NERSC account with a Perlmutter allocation (`mXXXX`; CPU and GPU jobs use the
  same account).
- ThinLinc client on the laptop: https://www.cendio.com/thinlinc/download (install steps
  for Windows, macOS and Linux: [page 9](../09-thinlinc-nionswift.md#install-the-client))
- `sshproxy` set up (https://docs.nersc.gov/connect/mfa/#sshproxy). The generated
  key (`nersc` in your `.ssh` folder by default; its full path on each OS is in
  [page 9](../09-thinlinc-nionswift.md#connect)) is valid 24 h and must be regenerated daily:

  ```bash
  sshproxy -u <nersc_username>
  ```

## 3. One-time: ThinLinc client configuration

1. Open ThinLinc client → `Options...` → `Security` tab → Authentication method:
   **Public Key**.
2. Connection settings:
   - Server: `thinlinc.nersc.gov`
   - User: NERSC username
   - Key: path to the sshproxy key (per OS: [page 9](../09-thinlinc-nionswift.md#connect), step 2)
3. On first connect, verify the host key fingerprint against
   https://docs.nersc.gov/connect/#key-fingerprints
4. Recommended: `Options...` → `Advanced` → Reconnect policy →
   *Always ask how multiple sessions should be handled*.

Notes:

- Keys generated inside WSL and mounted into Windows, and PuTTY PPK keys, do not
  work with ThinLinc. Use `sshproxy` natively.
- Inside the ThinLinc desktop there is a **Perlmutter button** that opens a
  graphics-enabled login shell on Perlmutter (equivalent to
  `ssh -X perlmutter.nersc.gov` from a ThinLinc terminal).

## 4. One-time: Python environment (uv; do this on a Perlmutter login node)

These notes are part of the group repository `IdroboLab/idrobolab-env`;
everyone works from their own clone at `~/idrobolab-env` (set up in
[page 2](../02-shell-setup.md#2-your-clone-of-idrobolab-env)):

```bash
git clone git@github.com:IdroboLab/idrobolab-env.git ~/idrobolab-env
```

Install into `/global/common/software/<project>/` — read-optimized for software,
mounted read-only on compute nodes (so install/update from a *login* node), and
much faster than `$HOME` for importing Python packages at scale.

The recommended route is **pip in a uv-managed venv** (PyPI is upstream's
preferred distribution nowadays). uv's Pythons are python-build-standalone
builds with `pyexpat` compiled *into* the interpreter — structurally immune
to the libexpat-shadowing crash that silently kills the launcher with
conda/distro Pythons (§7.6), so no `LD_PRELOAD` is needed. The interpreter
also only changes when *you* update it, unlike venvs seeded from the NERSC
`python` module, which NERSC replaces on upgrades.

```bash
source ~/idrobolab-env/perlmutter/env.sh   # sets UV_PYTHON_INSTALL_DIR
                                                       # (normally in ~/.bashrc already)

# install (or update) uv into the shared project bin dir — env.sh puts
# that dir on PATH for everyone. ALWAYS use this script, never
# `uv self update` or `cp -p` from a home dir: both leave the binary
# with the personal group/umask mode, which locks the rest of the
# project out (observed 2026-08: group member got "permission denied").
# The script chgrp's + setgids everything and verifies group access.
~/idrobolab-env/perlmutter/helpers/install-uv.sh

# python 3.13 pin: nionui 10.2.2/11.1.0 crashes on Python 3.14
# (asyncio.get_event_loop() implicit-loop removal) — verified 2026-08.
uv python install 3.13
uv venv --python 3.13 /global/common/software/mXXXX/venvs/nionswift-py313
uv pip install -p /global/common/software/mXXXX/venvs/nionswift-py313/bin/python \
    nionswift nionswift-tool nionswift-usim nionswift-eels-analysis \
    nionswift-experimental

# make it usable by the whole project group — group ownership AND mode
# (chmod alone is useless if files carry your personal group), plus
# setgid on dirs so future files inherit the project group:
chgrp -R mXXXX  "$UV_PYTHON_INSTALL_DIR" /global/common/software/mXXXX/venvs/nionswift-py313
chmod -R g+rX   "$UV_PYTHON_INSTALL_DIR" /global/common/software/mXXXX/venvs/nionswift-py313
find "$UV_PYTHON_INSTALL_DIR" /global/common/software/mXXXX/venvs/nionswift-py313 \
    -type d -exec chmod g+s {} +

# sanity: the venv's python must NOT resolve into anyone's $HOME (it does if
# UV_PYTHON_INSTALL_DIR was unset when the interpreter was installed — then
# group members cannot run it):
readlink -f /global/common/software/mXXXX/venvs/nionswift-py313/bin/python

/global/common/software/mXXXX/venvs/nionswift-py313/bin/nionswift    # launches
```

Group members need no uv of their own to *use* the env — running
`.../venvs/nionswift-py313/bin/nionswift` is all there is to it.

Alternatives (upstream-supported, but on Perlmutter both need the
`LD_PRELOAD` libexpat workaround because their `pyexpat` links libexpat
dynamically — full story in §7.6):

- nion conda channel:
  `conda create -p <prefix> -c nion python=3.13 nionswift nionswift-tool`,
  launch with `LD_PRELOAD="$CONDA_PREFIX/lib/libexpat.so.1" nionswift`.
- pip in a venv seeded from a conda/module Python: preload
  `$(python -c 'import sys; print(sys.base_prefix)')/lib/libexpat.so.1`.

Known constraint (from the Nion Swift docs): the `nionswift-tool` launcher bundles
its own Qt and **requires a PATH that contains no other Qt library directories**.
On Perlmutter, do not load modules that inject Qt into `PATH`/`LD_LIBRARY_PATH`
before launching. If unavoidable, drop `nionswift-tool` and use the PyQt backend
instead (see §7.3).

## 5. Per-session workflow: interactive compute node

From the graphics-enabled Perlmutter shell inside the ThinLinc desktop:

```bash
# CPU node (2x AMD Milan, 128 cores, 512 GB RAM) - default choice for large
# in-memory datasets:
salloc -N 1 -q interactive -t 4:00:00 -C cpu -A "$NERSC_PROJECT"

# GPU node variant (only if your processing actually uses GPUs; Swift itself
# does not). Note the explicit GPU request:
salloc -N 1 -q interactive -t 4:00:00 -C gpu --gpus 4 -A "$NERSC_PROJECT"

# Cheaper for look-heavy sessions: a slice of a node via the shared
# interactive QOS (size -c / --mem to the dataset; confirm the exact QOS
# name in the QOS table if the submission is rejected):
salloc -q shared_interactive -t 4:00:00 -C cpu -n 1 -c 32 --mem=120G -A "$NERSC_PROJECT"
```

Interactive QOS behavior: node delivery is targeted within 6 min; the request is
auto-cancelled after 6 min if resources are unavailable (extend the wait with
`--immediate=<seconds>`); max 4 nodes. Walltime cap is short — 4 h at the time of
writing; **verify** in https://docs.nersc.gov/jobs/policy/.

`salloc` drops the shell directly onto the compute node (prompt becomes
`...@nidXXXXXX`). Then:

```bash
echo $DISPLAY        # should be set (e.g. localhost:NN.0)
```

If `$DISPLAY` is empty, use the fallback: from the graphics-enabled login shell,
SSH into the allocated node with X forwarding (user SSH access to compute nodes is
enabled for the lifetime of the job):

```bash
squeue --me                    # find nidXXXXXX
ssh -X nidXXXXXX
```

Launch:

```bash
env HDF5_USE_FILE_LOCKING=FALSE /global/common/software/mXXXX/venvs/nionswift-py313/bin/nionswift
# (HDF5_USE_FILE_LOCKING: §7.7; conda-env alternative: activate it and launch with the §4 LD_PRELOAD)
```

First run: create the project/library on `$SCRATCH` (all-flash Lustre, intended
for active I/O). Scratch is subject to purging — keep master copies of data on
CFS or HPSS and treat the Swift library on scratch as a working copy.

### 5.1 One-click launcher from the ThinLinc desktop

A shared job script on Perlmutter plus a `.desktop` entry in each
member's ThinLinc-side home gives the ThinLinc desktop a menu item that
allocates a slice and launches Swift in one click. The launcher pieces
are user-independent (shared env, project account), so they install ONCE
into the project directories; only the `.desktop` entry is per-user,
because the ThinLinc hosts have their own home directories, separate from
the Perlmutter global home.

One-shot setup with `perlmutter/helpers/setup-nionswift-launcher.sh`. The
same script detects which machine it is on:

```bash
# 1. MAINTAINER, once, on a Perlmutter login node — installs the shared
#    job script, desktop entry, and icon under /global/common:
~/idrobolab-env/perlmutter/helpers/setup-nionswift-launcher.sh

# 2. EACH group member, once, in a terminal INSIDE the ThinLinc desktop
#    (separate home — fetch the script from Perlmutter, then run it):
scp perlmutter.nersc.gov:idrobolab-env/perlmutter/helpers/setup-nionswift-launcher.sh ~
~/setup-nionswift-launcher.sh
```

On Perlmutter it writes the shared pieces (knobs are variables at the
top, or `NIONSWIFT_ACCOUNT`/`NIONSWIFT_ENV`/`NIONSWIFT_DEFAULT_MEM_GB`/
`NIONSWIFT_DEFAULT_TIME`/`NIONSWIFT_SALLOC_OPTS` — the last one bakes
arbitrary extra salloc options into the job script, appended after the
sized arguments so they win where Slurm takes the last occurrence; a
`--mem*` in it suppresses the memory prompt AND the automatic sizing, so
it must then be a complete resource spec incl. QOS/constraint/CPUs, and
a `-t`/`--time` suppresses the walltime prompt; `-L <licenses>` declares the file
systems your data is on, [page 4](../04-jobs.md#file-system-licenses)); on a ThinLinc host it
sets up ssh auth, copies
the entry + icon from the shared location into the member's ThinLinc
home, adds a terminal launcher, and links both into the folder
`~/Desktop/IdroboLab` (§5.2, §5.4). No relogin needed: the
menu rescans on next open (`update-desktop-database
~/.local/share/applications` nudges it), the folder on the desktop is
immediate, and MATE may ask to mark a new launcher trusted on first click. What it
installs:

`/global/common/software/mXXXX/bin/nionswift-job.sh` (mode 755): the
generated job script is interactive — it runs in the terminal window the
`.desktop` entry opens (`Terminal=true`) and prompts for the session
size, then allocates and launches:

- **Memory in GB** (default 64) and **walltime** (default 4:00:00; a bare
  number is read as hours).
- Logical CPUs are derived from the Perlmutter CPU-node ratio — 512 GB /
  256 logical CPUs, i.e. 2 GB per CPU, rounded up (64 GB → `-c 32`), so
  the shared-QOS charge is memory- and CPU-proportional alike.
- **More than half a node (> 256 GB) switches to an exclusive full node
  on the `interactive` QOS** (`-N 1`, no `--mem`); anything at or below
  half a node uses `shared_interactive` with `-n 1 -c <cpus>
  --mem=<GB>G`. Mind the full-node charging caveat (§9) and the 4 h
  interactive walltime cap (§5).
- On bad input or a failed `salloc` it pauses ("press Enter to close")
  so the error stays readable before the terminal window closes.

Core allocation line (see the generated file for the full logic):

```bash
salloc -A mXXXX $SALLOC_ARGS -t "$TIME" -J nionswift \
     bash -c "ssh -Y \"\$SLURM_NODELIST\" 'env HDF5_USE_FILE_LOCKING=FALSE $ENV/bin/nionswift'"
```

(`salloc` runs its command on the *login* node, so the script uses the
ssh-to-allocated-node hop from §5; running `$ENV/bin/nionswift` directly
needs no activation — the entry script's shebang pins the env. The setup
script generates this file, and if the env is a conda one it inserts the
§7.6 `LD_PRELOAD` automatically — it detects `$ENV/lib/libexpat.so.1`.)

`/global/common/software/mXXXX/bin/nionswift-idrobolab`, a relative symbolic
link to `nionswift-job.sh`, so that a member can type `nionswift-idrobolab` in
a Perlmutter terminal (`env.sh` puts the directory on `PATH`). The job script
does not depend on how it is started: run that way it asks the same questions,
and its `ssh -Y` to the node needs the `$DISPLAY` of the ThinLinc session, which
a terminal opened from the Perlmutter button has.

`/global/common/software/mXXXX/share/nionswift/nionswift-perlmutter.desktop`
(plus `nionswift.png` beside it — §5.2 copies both to the ThinLinc side):

```ini
[Desktop Entry]
Type=Application
Name=Nion Swift (Perlmutter)
Comment=Allocate a compute-node slice and launch Nion Swift
Exec=ssh -Yt perlmutter.nersc.gov /global/common/software/mXXXX/bin/nionswift-job.sh
Icon=nionswift
Terminal=true
Categories=Science;Education;
```

Notes:

- `Terminal=true` matters: the terminal window hosts the session-size
  prompts, shows salloc queue progress and errors (an expired sshproxy
  cert, a stuck queue), and closing Swift tears down the whole chain and
  frees the allocation.
- The `-t` on the `Exec` ssh matters too: it allocates a remote pty, so
  closing the terminal window while the job is still **pending** delivers
  a SIGHUP to `salloc`, which then revokes the queued allocation itself.
  Without `-t`, an abandoned pending job stays in the queue until the
  interactive QOS times it out.
- The hops use `-Y` (trusted forwarding) rather than `-X`: untrusted
  forwarding needs the X server's SECURITY extension, which TigerVNC
  lacks, producing "Warning: untrusted X11 forwarding setup failed: xauth
  key data not generated" and — depending on the OpenSSH config — either
  a silent fallback to trusted anyway or no forwarding at all. Every hop
  here is between the user's own sessions on NERSC hosts, where trusted
  forwarding is the norm.
- `Exec` lines get no shell expansion — use the absolute script path.
- Icon: the setup script converts the Nion Swift logo (the launcher's
  bundled `Graphics/WinIcon.ico`, or — since the linux builds ship
  without it — the same file fetched from the nionswift-tool GitHub repo)
  to the shared `share/nionswift/nionswift.png` via the env's Pillow. The
  generated entry says `Icon=nionswift`; on the ThinLinc side the script
  copies the PNG into the member's home and rewrites `Icon=` to its
  absolute local path, because name-based icon lookup is unreliable on
  the ThinLinc hosts' older MATE/GTK (symptom: a generic text-file icon).
  Falls back to a stock icon if all of that fails.
- Folder icon: the setup script installs the group logo from
  `assets/idrobolab-folder.png` (a 256x256 PNG; the clone
  that runs the script supplies it) to `share/nionswift/idrobolab-folder.png`.
  If the file is missing from the clone, the script prints a note and goes on.
  Like writing the job script, installing the file and the
  `nionswift-idrobolab` link stops the script if the shared directory cannot be
  written. §5.4 covers the ThinLinc side.
- For non-interactive ThinLinc→Perlmutter auth, point ssh at the sshproxy
  key in `~/.ssh/config` — this must be on the **ThinLinc side**, where
  the `Exec` ssh runs (see §5.2 for getting the key there):

  ```
  Host perlmutter perlmutter.nersc.gov
      IdentityFile ~/.ssh/nersc
  ```

- This couples the session to the terminal/ssh chain — no idle
  allocations, but also no surviving a closed terminal. For detachable
  long sessions use the §6 hold-job pattern instead.

### 5.2 Installing the entry ThinLinc-side (separate home!)

The ThinLinc hosts have their **own home directory** — NOT the Perlmutter
global home. Observed on one ThinLinc host on 2026-10-07 (NERSC documents
none of this):

- `$HOME` prints `/global/homes/<x>/<username>` there, the same path as on
  Perlmutter, but `findmnt -T ~` shows that the directory is an NFS share
  of the ThinLinc machines themselves, not the Perlmutter global home.
- A file created in it did not appear in the Perlmutter home, and the
  Perlmutter home's snapshots never contained the launcher.
- It persists across sessions and logouts: `~/.ssh` and
  `~/.local/share/applications` survive.
- **`~/Desktop` is the exception.** It is reset whenever a new session
  starts after a complete logout: NERSC's own desktop files (`DTNs`,
  `Logout`, `Perlmutter`, `tl-disconnect`) are re-created there with the
  session's start time, and other files and links lying directly in
  `~/Desktop`, such as a link to the launcher, are gone. Folders in
  `~/Desktop` survive the reset with their contents. Reconnecting to a
  running session does not reset it. §5.4 deals with this.

The `.desktop` entry has to live in the home the ThinLinc
desktop reads, while the job script stays on Perlmutter in the shared
project bin (it is executed there by the `ssh` in the `Exec` line).
Running the setup script on the ThinLinc host (§5.1, step 2) does all of
this section automatically; the manual equivalent — from a terminal
*inside the ThinLinc desktop*:

```bash
mkdir -p ~/.local/share/applications ~/Desktop/IdroboLab
scp perlmutter.nersc.gov:/global/common/software/mXXXX/share/nionswift/nionswift-perlmutter.desktop \
    ~/.local/share/applications/
chmod +x ~/.local/share/applications/nionswift-perlmutter.desktop
ln -sf ~/.local/share/applications/nionswift-perlmutter.desktop ~/Desktop/IdroboLab/
```

Members re-run the ThinLinc step whenever the maintainer re-runs the
Perlmutter step with changed settings.

Then verify the launcher's ssh hop works without a password prompt, again
from the ThinLinc terminal:

```bash
ssh perlmutter.nersc.gov true
```

If this prompts, the ThinLinc-side `~/.ssh` needs the sshproxy key too:
run `sshproxy -u <username>` inside the ThinLinc session and put the
`Host perlmutter` / `IdentityFile ~/.ssh/nersc` block (§5.1) in the
ThinLinc-side `~/.ssh/config`. The 24 h key lifetime then applies to the
launcher: with an expired key the launcher's terminal window shows the
prompt/failure — that is expected, regenerate the key.

### 5.3 Launching from the keyboard inside ThinLinc

Both desktops NERSC's ThinLinc offers have a run dialog:

- **MATE**: `Alt+F2` → Run Application (has a "Run in terminal" checkbox).
- **XFCE**: `Alt+F2` → Application Finder (compact); `Alt+F3` full view.

In the dialog, launch the entry with:

```
gtk-launch nionswift-perlmutter
```

(`gtk-launch` runs the `.desktop` entry properly, including its
`Terminal=true`; typing the raw `ssh` command instead would need "Run in
terminal" ticked by hand.)

On NERSC's ThinLinc desktop, Nion Swift starts from the `Alt+F2` run
dialog, without any desktop icon: the dialog finds the entry in
`~/.local/share/applications/`, which persists.

Two gotchas and their fixes:

- **The combo opens your LOCAL launcher instead.** Your own desktop grabs
  `Alt+F2` before the ThinLinc client sees it. Either press `F8` inside
  the ThinLinc window (the client's popup menu — it is TigerVNC-based)
  and choose *Full screen* or *Grab keyboard*, after which all keys go to
  the remote session; or use a combo your local desktop does not own
  (next point).
- **One-keystroke launch**: bind the command to a custom shortcut *in the
  remote desktop*, picking a combo that does not collide locally (e.g.
  `Ctrl+Alt+N`): MATE: System → Preferences → Hardware → Keyboard
  Shortcuts → Add, command `gtk-launch nionswift-perlmutter`. XFCE:
  Settings → Keyboard → Application Shortcuts → Add. This passes through
  even in windowed mode.

### 5.4 After a new session: the IdroboLab folder and the terminal launcher

Because the reset of `~/Desktop` at the start of a new session removes
links lying directly in it but keeps folders and their contents (§5.2),
the setup script puts its desktop links in the folder
`~/Desktop/IdroboLab`, in the ThinLinc-side home:

- `~/Desktop/IdroboLab/nionswift-perlmutter.desktop` and
  `~/Desktop/IdroboLab/thinlinc-terminal.desktop`, symbolic links to the
  two launchers in `~/.local/share/applications/`.
- `~/.local/share/applications/thinlinc-terminal.desktop`, a launcher with
  `Exec=bash -l` and `Terminal=true` (the key the Desktop Entry
  Specification defines for programs that run in a terminal window): it
  opens a login shell **on the ThinLinc host** in the desktop's own
  terminal emulator. Opening a plain terminal there is otherwise hard
  for members, and the sshproxy step (§5.2) needs one. It is executable
  like the Nion Swift launcher, and both launchers are also in the
  applications menu.
- The icon of the folder itself: the script copies the group logo from
  the shared `share/nionswift/idrobolab-folder.png` (§5.1) to
  `~/.local/share/icons/idrobolab-folder.png` and, if `gio` exists, runs
  `gio set ~/Desktop/IdroboLab metadata::custom-icon file://$HOME/.local/share/icons/idrobolab-folder.png`.
  A failing `scp` or `gio` only prints a note; the folder then keeps its stock
  icon.

Re-running the setup script overwrites these files; nothing is duplicated.
It also removes what older versions of it installed for the same purpose:
the autostart entry `~/.config/autostart/idrobolab-desktop-links.desktop`,
which re-created links directly on `~/Desktop` at every session start, and
those links themselves. The copy of the script in the ThinLinc home does
not update itself: to migrate, pull the clone on Perlmutter, fetch the
script again (§5.1) and run it.

Caja (MATE) shows the folder icon set through `gio` (it reads GVFS metadata
for that): checked on the ThinLinc desktop with the same `scp` and `gio set`
commands the script runs.

Not verified, because it can only be tested on the ThinLinc desktop:
whether symbolic links inside `~/Desktop/IdroboLab`
survive a new session as the folder does, and whether Caja launches them
from the folder;
whether `Terminal=true` opens a terminal on that desktop (the Nion Swift
launcher already relies on it, §5.1); and whether ticking "Run in terminal"
in the run dialog (§5.3) gives a first terminal there.

## 6. Longer sessions (> interactive walltime)

Submit a placeholder batch job, then attach with `ssh -X`:

```bash
cat > hold_node.sh <<'EOF'
#!/bin/bash
#SBATCH -A mXXXX
#SBATCH -C cpu
#SBATCH -q regular          # or: -q shared with -n 1 -c 32 --mem=120G
#SBATCH -N 1
#SBATCH -t 12:00:00
#SBATCH -J nionswift-hold
sleep infinity
EOF
sbatch hold_node.sh
squeue --me                 # wait for R state, note nidXXXXXX
ssh -X nidXXXXXX
```

Regular and shared QOS allow up to 24 h walltime. Remember: an exclusive node in
`regular` is charged for the full wallclock, including think-time — for sessions
dominated by looking rather than computing, `shared` is substantially cheaper.
`scancel` the hold job when done; do not let it idle to walltime.

## 7. Troubleshooting

Expected friction points, in order of probability. The compute-node OS image is
minimal (NERSC's own docs note Perlmutter does not ship X Window utilities), so
everything X/Qt must come from the conda env.

If `nionswift` prints only "Using Python environment: ..." and returns to the
prompt with exit 0 — no window, no error — go straight to §7.6: the wrapper
swallows launcher crashes.

### 7.1 Qt xcb platform plugin fails to load

Symptom: `qt.qpa.plugin: Could not load the Qt platform plugin "xcb"`.

```bash
export QT_DEBUG_PLUGINS=1    # rerun to see which .so is missing
```

Fix by adding the missing X client libs to the env from conda-forge, e.g.:

```bash
conda install -c conda-forge xorg-libx11 xorg-libxext xorg-libxrender \
    xorg-libxrandr xorg-libxcursor xorg-libxi libxcb xcb-util-keysyms \
    xcb-util-image xcb-util-renderutil xcb-util-wm
```

### 7.2 OpenGL errors / blank or crashing windows

There is no usable GLX/hardware GL across this display chain. Force software
rendering:

```bash
export QT_XCB_GL_INTEGRATION=none
export QT_OPENGL=software
export LIBGL_ALWAYS_SOFTWARE=1
# if libGL itself is missing:
conda install -c conda-forge mesalib
```

### 7.3 nionswift-tool launcher misbehaves (Qt/PATH conflict, launcher crash)

Documented fallback — switch to the pure-Python Qt backend. With
`nionswift-tool` absent, `nion.swift.command.main()` falls back to PySide6
in-process (no native launcher involved), so errors surface normally:

```bash
conda remove nionswift-tool
conda install -c conda-forge pyside6   # (pip install PySide6 in a venv setup)
# required with nionswift 16.16.2 / nionui 10.2.2 — see §4 for why:
sed -i.orig 's/{"pyqt": None}/{"qt": None}/' \
    "$CONDA_PREFIX/lib/python3.13/site-packages/nion/swift/command.py"
nionswift
```

Notes: the upstream Nion docs historically said PyQt5, but PyQt5 has no
builds for current Python versions; the fallback chain in
`nion.swift.command` tries PySide6. On Perlmutter the native launcher
works with the libexpat preload (§4/§7.6), so this fallback is only
needed if the preload route breaks; both routes verified 2026-08. A conda
update of nionswift reverts the sed patch above.

### 7.4 X authorization errors on `ssh -X` to the node

The ThinLinc host's home is separate from the Perlmutter home (§5.2), but that
does not matter here: the second hop, `ssh -Y` from the login node to the
compute node, is between two Perlmutter nodes, which share the Perlmutter global
home and so its `~/.Xauthority`. The ThinLinc side only needs a valid
`$DISPLAY` and its own cookie in the ThinLinc home, which the session creates.
This reading follows from the two homes and was not tested separately. If
forwarding is refused, re-check that the *originating* shell (ThinLinc → login)
has a valid `$DISPLAY` first; a broken first hop propagates.

### 7.5 Sluggish UI

Confirm the laptop↔NERSC leg is the ThinLinc protocol, not plain `ssh -X` end to
end. Reduce the Swift window size; screen-sized redraws are the dominant cost.
There is no VirtualGL-style GPU-accelerated remote rendering in this chain.

### 7.6 `nionswift` exits silently (exit 0, no window, no output)

The `nionswift` entry point is a thin wrapper: `nion.nionswift_tool.command.
launch()` runs the native launcher via `subprocess.Popen(...).communicate()`
and **discards its exit code** — a segfaulting launcher is indistinguishable
from a clean exit. Debug by invoking the native binary directly, exactly as
the wrapper does (env prefix and app package as arguments):

```bash
QT_DEBUG_PLUGINS=1 QT_LOGGING_RULES='qt.qpa.*=true' \
  "$CONDA_PREFIX/bin/NionSwiftLauncher/NionSwiftLauncher" "$CONDA_PREFIX" nionui_app.nionswift
echo "exit: $?"        # 139 = segfault
```

This surfaces the launcher's real stderr and exit code. Useful triage on top
of that:

```bash
python -m tkinter                       # X display chain OK? (no xeyes on Perlmutter)
ldd "$CONDA_PREFIX/bin/NionSwiftLauncher/NionSwiftLauncher" | grep -i "not found"
gdb -batch -ex run -ex bt --args \
  "$CONDA_PREFIX/bin/NionSwiftLauncher/NionSwiftLauncher" "$CONDA_PREFIX" nionui_app.nionswift
```

Two more debugging notes for this failure mode:

- `PYTHONFAULTHANDLER=1 <launcher> "$CONDA_PREFIX" nionui_app.nionswift`
  prints the Python stack at the moment of a segfault to the real stderr
  (file descriptor 2), bypassing all output redirection.
- The launcher's `bin/NionSwiftLauncher/bootstrap.py` replaces
  `sys.stdout`/`sys.stderr` with a catcher routed into the C++ host as its
  very first action, so Python tracebacks during bootstrap are invisible if
  the host dies. When debugging, comment out the two `sys.stdout`/`sys.stderr`
  assignment lines there (keep a `.orig` backup), or write diagnostics with
  `os.write(2, ...)`.

Root cause on Perlmutter (found 2026-08-26, affects any host whose system
libexpat is older than the env's — SLES 15 qualifies): the launcher's
bundled Qt loads the **system** `libexpat.so.1` via fontconfig; when the
embedded Python later imports `pyexpat` (via `nion.swift.Facade` →
`xmlrpc.server`), the linker reuses that old copy and the import dies with
`undefined symbol: XML_SetHashSalt16Bytes`. The launcher's `bootstrap.py`
swallows the ImportError (`except ImportError: pass`) and reports "no
main"; launcher ≤5.2.0 then `Py_INCREF`s the null result — SIGSEGV in
`Application::initialize()` — while 5.3.0 exits 0 cleanly. Either way:
silent, windowless, no app log, on any display and every launcher version
5.0.0–5.3.0, conda and pip, Python 3.12–3.14. (The identical version set
works on a laptop with a recent system libexpat, which is what finally
isolated it.)

**Fixes**, strongest first:

- Structural (the §4 default): use a uv-managed Python —
  python-build-standalone compiles `pyexpat` into the interpreter, so
  there is no dynamic libexpat for the launcher to shadow. Verify with
  `python -c "import sys; print('pyexpat' in sys.builtin_module_names)"`.
- Workaround for conda/module Pythons: preload the env's libexpat —
  `LD_PRELOAD="$CONDA_PREFIX/lib/libexpat.so.1" nionswift` (for a venv on
  such a base: preload from `sys.base_prefix` instead).
- Last resort: PySide6 backend (§7.3).

Reported upstream 2026-08-26 as
https://github.com/nion-software/nionswift/issues/1946 (don't swallow the
ImportError, null-check the bootstrap result, propagate the wrapper exit
code, isolate the bundled Qt from system libexpat).

### 7.7 `Error reading ... .h5 ([Errno 524] ... unable to lock file ...)`

Swift reports this for every data file of a project on CFS (or `$HOME`).
HDF5 takes a `flock` on each file it opens, and these file systems, as the
compute nodes mount them, do not support it (errno 524 is `ENOTSUPP`).
Start Swift with `HDF5_USE_FILE_LOCKING=FALSE`: the job script from §5.1
does, and §5 shows it for a manual launch. The shared job script gets it
when the maintainer re-runs `setup-nionswift-launcher.sh` (§5.1, step 1).

Nothing then stops two Swift sessions from opening the same project, on
any file system, and the second one can overwrite the first one's
changes. HDF5's lock covers a data file only while it is open, and never
the project index (`.nsproj`), so it did not prevent that either. Open a
project in one Swift session at a time.

## 8. Sanity-check sequence for first bring-up

1. ThinLinc desktop opens; terminal works.
2. Perlmutter shell via the Perlmutter button; `echo $DISPLAY` non-empty.
3. `salloc` CPU node; `echo $DISPLAY` non-empty on `nidXXXXXX`
   (else `ssh -X nidXXXXXX` from step 2's shell).
4. `conda activate ...; nionswift` — window appears in the ThinLinc desktop.
5. Create test library on `$SCRATCH`; import a dataset; check redraw latency is
   tolerable before committing to this workflow.

## 9. When *not* to use this

The GUI-on-compute-node pattern is justified when the point is interactive
inspection of large datasets next to `$SCRATCH` with 512 GB RAM — login nodes are
explicitly the wrong place for that (per-user cgroup CPU/memory limits, and NERSC
policy sends long/large interactive work to the batch QOSes).

If the actual driver is *computation* (batch processing of Swift libraries,
parameter sweeps), skip the GUI: read the library's underlying HDF5/ndata files
directly in headless Python jobs. A GUI session burns allocation while idle;
batch jobs do not.

## References

- ThinLinc at NERSC: https://docs.nersc.gov/connect/thinlinc/
- Host key fingerprints: https://docs.nersc.gov/connect/#key-fingerprints
- sshproxy / MFA: https://docs.nersc.gov/connect/mfa/#sshproxy
- Interactive jobs: https://docs.nersc.gov/jobs/interactive/
- QOS limits and charges: https://docs.nersc.gov/jobs/policy/
- SSH to compute nodes (job lifetime): https://docs.nersc.gov/jobs/monitoring/
- Resource usage policy (login-node limits): https://docs.nersc.gov/policies/resource-usage/
- Python at NERSC: https://docs.nersc.gov/development/languages/python/nersc-python/
- Nion Swift installation: https://nionswift.readthedocs.io/en/stable/installation.html
