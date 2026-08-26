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

Install into `/global/common/software/<project>/` — read-optimized for software,
mounted read-only on compute nodes (so install/update from a *login* node), and
much faster than `$HOME` for importing Python packages at scale.

```bash
module load python    # NERSC-provided Anaconda-based Python; own Miniforge also fine

# As of 2026-08 the linux nionswift-tool launcher (all of 5.0.0–5.3.0,
# conda and pip, any Python) fails silently when run on Perlmutter login
# nodes, regardless of display route (see §7.6). Until resolved, skip
# nionswift-tool and use the PySide6 backend (§7.3):
conda create -p /global/common/software/mXXXX/$USER/nionswift \
    -c nion python=3.13 nionswift
conda install -p /global/common/software/mXXXX/$USER/nionswift \
    -c conda-forge pyside6

conda activate /global/common/software/mXXXX/$USER/nionswift

# ...and the PySide6 fallback needs a one-word patch (verified working
# 2026-08): nionswift's command.py passes bootstrap key "pyqt" but nionui's
# make_ui only accepts "proxy"/"qt", so unpatched it dies with "Unable to
# create user interface object". A conda update of nionswift reverts this.
sed -i.orig 's/{"pyqt": None}/{"qt": None}/' \
    "$CONDA_PREFIX/lib/python3.13/site-packages/nion/swift/command.py"

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
conda activate /global/common/software/mXXXX/$USER/nionswift
nionswift
```

First run: create the project/library on `$SCRATCH` (all-flash Lustre, intended
for active I/O). Scratch is subject to purging — keep master copies of data on
CFS or HPSS and treat the Swift library on scratch as a working copy.

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
`nion.swift.command` tries PySide6. Downgrading or switching channels does
NOT help: 5.0.0/5.1.5/5.2.0 (conda) and 5.3.0 (pip) all fail on Perlmutter
(§7.6) — the PySide6 backend is the only route verified working there
(2026-08).

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

Known instance (2026-08): the native launcher fails whenever it runs **on
a Perlmutter login node**, regardless of display — ThinLinc/TigerVNC and
`ssh -X` to a known-good laptop X server fail identically, while the
byte-for-byte identical version set runs fine *on* that laptop (local
display, forced `QT_QPA_PLATFORM=xcb`, even with `QT_XCB_NO_MITSHM=1`).
So the trigger is the host environment, not the display, X transport,
SHM, OpenGL (software-GL vars change nothing; GL libs present), config,
Python (3.12–3.14), packaging channel (conda and pip), or launcher
version (5.0.0–5.3.0; 5.0–5.2 segfault in C++
`Application::initialize()` — `QVariant::value<PyObjectPtr>()` →
`Py_INCREF` on an invalid pointer — *after* the Python bootstrap
completes, 5.3.0 exits 0 cleanly, still windowless). Prime suspect: Qt
library contamination from the login-node environment (see the §4 note
that the launcher must not see other Qt directories); triage with a
sanitized run:
`env -i DISPLAY=$DISPLAY XAUTHORITY=$HOME/.Xauthority HOME=$HOME
PATH=/usr/bin:/bin <launcher> <prefix> nionui_app.nionswift`.
Fix: PySide6 backend (§4, §7.3). Upstream report drafted 2026-08-26 (post
to nion-software/nionswift — the nionswift-tool repo restricts issues).

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
