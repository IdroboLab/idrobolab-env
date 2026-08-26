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

- NERSC account with a Perlmutter allocation (`mXXXX`; GPU allocations are the
  `mXXXX_g` variant).
- ThinLinc client on the laptop: https://www.cendio.com/thinlinc/download
- `sshproxy` set up (https://docs.nersc.gov/connect/mfa/#sshproxy). The generated
  key (`~/.ssh/nersc` by default) is valid 24 h and must be regenerated daily:

  ```bash
  sshproxy -u <nersc_username>
  ```

## 3. One-time: ThinLinc client configuration

1. Open ThinLinc client → `Options...` → `Security` tab → Authentication method:
   **Public Key**.
2. Connection settings:
   - Server: `thinlinc.nersc.gov`
   - User: NERSC username
   - Key: path to the sshproxy key (`~/.ssh/nersc`)
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

## 4. One-time: conda environment (do this on a Perlmutter login node)

**Group members**: this directory is already available on Perlmutter in
the shared project checkout at `/global/cfs/cdirs/<project>/env` (sparse
checkout of `perlmutter/` + `shared/`) — use it directly, no GitHub
access needed:

```bash
ls /global/cfs/cdirs/<project>/env/perlmutter/
```

**Maintainers** (or for a personal copy): the repo is private, so cloning
needs collaborator access and a GitHub personal access token (fine-grained,
"Contents: Read-only"; used as the https password — account passwords are
rejected). Sparse checkout of `perlmutter/` only (portable sequence; the
shorter `git clone --sparse` is broken on older gits such as the ThinLinc
hosts' 2.25):

```bash
git clone --filter=blob:none --no-checkout https://github.com/<username>/hpcenvs.git
cd hpcenvs
git sparse-checkout init --cone
git sparse-checkout set perlmutter
git checkout main
git config pull.rebase true    # repo convention; see top-level CLAUDE.md
```

(`--filter=blob:none` downloads file contents only as needed;
`sparse-checkout set` restricts the working tree to the named dirs plus
top-level files, and a later `git sparse-checkout set <dirs...>` widens
it.)

Install into `/global/common/software/<project>/` — read-optimized for software,
mounted read-only on compute nodes (so install/update from a *login* node), and
much faster than `$HOME` for importing Python packages at scale.

```bash
module load python    # NERSC-provided Anaconda-based Python; own Miniforge also fine

# python=3.13 pin: nionui 10.2.2 crashes on Python 3.14
# (asyncio.get_event_loop() implicit-loop removal) — verified 2026-08.
conda create -p /global/common/software/mXXXX/$USER/nionswift-py313 \
    -c nion python=3.13 nionswift nionswift-tool

conda activate /global/common/software/mXXXX/$USER/nionswift-py313

# LD_PRELOAD is REQUIRED on Perlmutter (verified 2026-08): the launcher's
# bundled Qt loads the old SLES system libexpat via fontconfig, which then
# shadows the conda env's libexpat when Python imports pyexpat — the app
# dies silently without it. Full story + debugging chain: §7.6.
alias nionswift='LD_PRELOAD="$CONDA_PREFIX/lib/libexpat.so.1" nionswift'

# Optional EELS tooling (also available via conda where packaged):
pip install nionswift-eels-analysis
```

Alternatives (all upstream-supported):

- conda-forge channel: `conda create -n nionswift -c conda-forge nionswift nionswift-tool`
- pip in a venv: `pip install nionswift nionswift-tool`

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
salloc -N 1 -q interactive -t 4:00:00 -C cpu -A mXXXX

# GPU node variant (only if your processing actually uses GPUs; Swift itself
# does not). Note the _g account and explicit GPU request:
salloc -N 1 -q interactive -t 4:00:00 -C gpu --gpus 4 -A mXXXX_g

# Cheaper for look-heavy sessions: a slice of a node via the shared
# interactive QOS (size -c / --mem to the dataset; confirm the exact QOS
# name in the QOS table if the submission is rejected):
salloc -q shared_interactive -t 4:00:00 -C cpu -n 1 -c 32 --mem=120G -A mXXXX
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
conda activate /global/common/software/mXXXX/$USER/nionswift-py313
LD_PRELOAD="$CONDA_PREFIX/lib/libexpat.so.1" nionswift   # preload required — see §4/§7.6
```

First run: create the project/library on `$SCRATCH` (all-flash Lustre, intended
for active I/O). Scratch is subject to purging — keep master copies of data on
CFS or HPSS and treat the Swift library on scratch as a working copy.

### 5.1 One-click launcher from the ThinLinc desktop

A job script on Perlmutter plus a `.desktop` entry in the ThinLinc-side
home gives the ThinLinc desktop a menu item that allocates a slice and
launches Swift in one click. Note the ThinLinc hosts have their own home
directory, separate from the Perlmutter global home — the setup script
below installs everything Perlmutter-side, and §5.2 copies the entry to
the ThinLinc side.

One-shot setup with `setup-nionswift-launcher.sh` (this directory). The
same script detects which machine it is on — run it **twice, Perlmutter
first**:

```bash
# 1. on a Perlmutter login node:
/global/cfs/cdirs/<project>/env/perlmutter/setup-nionswift-launcher.sh

# 2. in a terminal INSIDE the ThinLinc desktop (separate home — fetch the
#    script from Perlmutter first, then run it):
scp perlmutter.nersc.gov:/global/cfs/cdirs/<project>/env/perlmutter/setup-nionswift-launcher.sh ~
~/setup-nionswift-launcher.sh
```

On Perlmutter it writes the job script and desktop entry (account/env/
salloc knobs are variables at the top, or `NIONSWIFT_ACCOUNT`/
`NIONSWIFT_ENV`/`NIONSWIFT_SALLOC_OPTS`); on the ThinLinc host it sets up
ssh auth, copies the entry over, and links it onto `~/Desktop` (§5.2). No
relogin needed: the menu rescans on next open (`update-desktop-database
~/.local/share/applications` nudges it), the Desktop icon is immediate,
and MATE may ask to mark a new launcher trusted on first click. The
manual steps it automates:

Neither target directory exists by default — create both first:

```bash
mkdir -p ~/bin ~/.local/share/applications
```

`~/bin/nionswift-job.sh` (then `chmod +x` it):

```bash
#!/bin/bash
# Allocate a shared-QOS slice and run Nion Swift on the compute node,
# with X forwarded back through this login node. Closing Swift (or the
# ssh dropping) ends the command and releases the allocation.

ENV=/global/common/software/mXXXX/$USER/nionswift-py313

exec salloc -A mXXXX -q shared_interactive -C cpu -n 1 -c 32 --mem=120G \
     -t 04:00:00 -J nionswift \
     bash -c "ssh -X \"\$SLURM_NODELIST\" 'LD_PRELOAD=$ENV/lib/libexpat.so.1 $ENV/bin/nionswift'"
```

(`salloc` runs its command on the *login* node, so the script uses the
ssh-to-allocated-node hop from §5; running `$ENV/bin/nionswift` directly
needs no `conda activate` — the entry script's shebang pins the env.)

`~/.local/share/applications/nionswift-perlmutter.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Nion Swift (Perlmutter)
Comment=Allocate a compute-node slice and launch Nion Swift
Exec=ssh -X perlmutter.nersc.gov /global/homes/<x>/<user>/bin/nionswift-job.sh
Icon=utilities-system-monitor
Terminal=true
Categories=Science;Education;
```

Notes:

- `Terminal=true` matters: the terminal window shows salloc queue progress
  and errors (an expired sshproxy cert, a stuck queue), and closing Swift
  tears down the whole chain and frees the allocation.
- `Exec` lines get no shell expansion — use the absolute script path.
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
global home. The `.desktop` entry has to live in the home the ThinLinc
desktop reads, while the job script stays on Perlmutter (it is executed
there by the `ssh` in the `Exec` line). Running the setup script on the
ThinLinc host (§5.1, step 2) does all of this section automatically; the
manual equivalent — from a terminal *inside the ThinLinc desktop*:

```bash
mkdir -p ~/.local/share/applications ~/Desktop
scp perlmutter.nersc.gov:.local/share/applications/nionswift-perlmutter.desktop \
    ~/.local/share/applications/
ln -sf ~/.local/share/applications/nionswift-perlmutter.desktop ~/Desktop/
```

Re-run this copy whenever the setup script is re-run with changed
settings.

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

`$HOME` (and thus `~/.Xauthority`) is shared, so xauth normally just works. If
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

**Fix: preload the env's libexpat** (this is the §4/§5 launch command):

```bash
LD_PRELOAD="$CONDA_PREFIX/lib/libexpat.so.1" nionswift
```

Alternative: PySide6 backend (§7.3). Upstream report drafted 2026-08-26
(post to nion-software/nionswift — the nionswift-tool repo restricts
issues): four fixes suggested (don't swallow the ImportError, null-check
the bootstrap result, propagate the wrapper exit code, isolate the
bundled Qt from system libexpat).

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
