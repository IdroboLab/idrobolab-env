# Jupyter on Perlmutter

Two ways to get a notebook running against our container images or shared
environments. They are complements, not rivals.

| | **A. jupyter.nersc.gov** | **B. Your own allocation + ssh tunnel** |
|---|---|---|
| Set up with | [`perlmutter/helpers/install-jupyter-kernel.sh`](../../../perlmutter/helpers/install-jupyter-kernel.sh) | [`perlmutter/jobs/interactive_jupyter.sh`](../../../perlmutter/jobs/interactive_jupyter.sh) |
| Tunnel | none | `ssh -L`, one line, printed for you |
| Terminal to keep open | none | yes — closing it ends the session |
| Survives a dropped laptop connection | yes | no |
| Node allocated by | NERSC (the hub asks you) | you (`salloc`, your QOS and walltime) |
| Runs | the env you registered as a kernel | the exact image the batch jobs use |
| Best for | day-to-day analysis | reproducing a production run, debugging a job |

Rule of thumb: **A for analysis, B for reproducing batch work.** If you are
about to write a `.sbatch` for it, prototype in B so the environment matches.

---

## A. jupyter.nersc.gov

Register a kernel once, on a login node. It then appears in the JupyterHub
launcher.

```bash
cd ~/idrobolab-env/perlmutter/helpers

# a shared uv/virtualenv venv
./install-jupyter-kernel.sh --venv /global/common/software/<project>/venvs/analysis \
                            --name analysis --display "Analysis (venv)"

# a conda env
./install-jupyter-kernel.sh --conda ~/.conda/envs/myenv --name myenv

# one of our container images
./install-jupyter-kernel.sh --image idrobolab --name idrobolab \
                            --display "idrobolab (GPU)" --gpu
```

Then <https://jupyter.nersc.gov> → start a Perlmutter server → pick the kernel.
**A new kernel does not appear in a server that is already running** — restart
it from the Hub Control Panel.

Managing them:

```bash
./install-jupyter-kernel.sh --list
./install-jupyter-kernel.sh --remove idrobolab
./install-jupyter-kernel.sh --venv ... --name analysis --force   # replace
./install-jupyter-kernel.sh --image ... --dry-run                # inspect first
```

Kernels are written to `~/.local/share/jupyter/kernels/<name>/kernel.json`.

### Moving a personal kernel to the shared tree

```bash
cd ~/idrobolab-env/perlmutter/helpers
. ../env.sh                                   # container kernels need the image store

./install-jupyter-kernel.sh --remove idrobolab                       # 1. drop the personal copy
./install-jupyter-kernel.sh --image idrobolab --name idrobolab \
                            --gpu --shared                            # 2. install project-wide
./install-jupyter-kernel.sh --link                                    # 3. link it back
```

Step 1 is not optional: `--link` refuses to replace a real directory, so a
leftover personal kernel of the same name would silently shadow the shared one.
Restart the Jupyter server from the Hub Control Panel afterwards.

`--remove` on a linked kernel deletes only your symlink — the shared original
is untouched — and it also clears a symlink left dangling by a shared kernel
that has since been removed. `--link` prunes those too.

### One kernel for the whole project

The maintainer installs into the project tree on `/global/common`, once:

```bash
. ~/idrobolab-env/perlmutter/env.sh
./install-jupyter-kernel.sh --image idrobolab --name idrobolab --gpu --shared
```

`--shared` writes to `/global/common/software/$NERSC_PROJECT/share/jupyter/kernels`
and makes it group-readable — the same tree `install-uv.sh` uses, and the same
reason: a file left at the default `0600` is useless to everyone else.

Jupyter does not search that location, so each user runs this once:

```bash
~/idrobolab-env/perlmutter/helpers/install-jupyter-kernel.sh --link
```

`~/.local/share/jupyter/kernels` is always searched, so a symlink there needs
nothing else configured. The `kernel.json` stays in the project tree, so
updating it there updates it for everyone. `--link` is idempotent, prunes links
whose shared kernel has gone, and skips any name where a real directory already
exists rather than clobbering someone's own kernel.

### venv and conda

Both run the environment's `bin/python` by absolute path. That is deliberate:
`conda run` captures output by default and breaks interactive kernels, and
`conda activate` needs a shell whose rc files the hub never sources. An env's
`bin/python` already has the right `sys.prefix` baked in, which is all a kernel
needs — so conda and venv are the same mechanism here.

The env must have `ipykernel` installed; the installer refuses otherwise,
because that failure would otherwise appear much later as an unrelated-looking
traceback at first use.

```bash
uv pip install --python /path/to/venv/bin/python ipykernel
```

### Containers

The kernel is `podman-hpc run ... python -m ipykernel_launcher -f {connection_file}`,
and two flags in it are load-bearing:

- **`--network host`.** A kernel is not a server you connect *to* — the hub
  connects *into* it, on the five ZMQ ports named in the connection file.
  podman-hpc containers get a private network namespace, so those ports are
  unreachable, and `-p` cannot help because the ports are chosen per launch.
- **`-v $HOME:$HOME` and `-e HOME=$HOME`.** The hub writes the connection file
  under `$HOME` and passes its path; the container has to see the same path.

Verified end to end on 2026-08-27: a container kernel runs on
jupyter.nersc.gov, reporting `sys.prefix` `/opt/venv` and Ubuntu 24.04 from
nid004142. The checks that established it are kept below, as the way to
diagnose a container kernel that will not start.

### Verifying a container kernel

Four checks, cheapest first. Stop at the first failure — each one is a
prerequisite for the next.

**1. Does podman-hpc accept the flag at all?** Login node, seconds.

```bash
podman-hpc run --rm --network host ghcr.io/<username>/idrobolab:latest true; echo "exit=$?"
```

`exit=0` means the flag is accepted. An "unknown flag" error means container
kernels are not possible this way and only the venv backend works.

**2. Does it actually give the host network namespace?** This is the check that
matters, because acceptance is not the same as effect. On a compute node
(`perlmutter/jobs/interactive_gpu.sh` gets you a shell), in one terminal:

```bash
podman-hpc run --rm --network host ghcr.io/<username>/idrobolab:latest \
    python3 -m http.server 8899 --bind 0.0.0.0
```

and in a second shell **on that same node**:

```bash
ss -ltn | grep 8899          # expected: a listener, WITHOUT any -p flag
curl -sI http://localhost:8899/
```

A listener here — where the same command without `--network host` shows
nothing — is host networking working. That is the whole premise of the
container kernel. Observed 2026-08-27 on nid001084:

```
$ ss -ltn | grep 8899
LISTEN 0      0            0.0.0.0:8899       0.0.0.0:*
```

**3. Does an ipykernel in the container answer from outside?** This is what the
hub does, and you can prove it without the hub. Install the kernel, then drive
it with `jupyter_client` from a host-side python:

```bash
./install-jupyter-kernel.sh --image idrobolab --name idrobolab --gpu
module load python                      # any python with jupyter_client
python - <<'EOF'
from jupyter_client.manager import start_new_kernel
km, kc = start_new_kernel(kernel_name="idrobolab")
kc.execute("import sys; print('prefix:', sys.prefix)")
import queue
while True:
    m = kc.get_iopub_msg(timeout=60)
    if m["msg_type"] == "stream":
        print("kernel said:", m["content"]["text"].strip()); break
kc.stop_channels(); km.shutdown_kernel()
EOF
```

`prefix: /opt/venv` proves the kernel ran **inside the container** and that the
ZMQ ports were reachable from outside it. A hang means the ports are not
reachable — check 2 failed, or `--network host` is accepted but ineffective.

**4. On the hub itself.** Install the kernel *after* sourcing `env.sh`, so the
shared image store is baked in — the hub launches kernels without a login
shell, so `~/.bashrc` never runs:

```bash
. ~/idrobolab-env/perlmutter/env.sh
~/idrobolab-env/perlmutter/helpers/install-jupyter-kernel.sh \
    --image idrobolab --name idrobolab --gpu --force
```
 <https://jupyter.nersc.gov> → start a Perlmutter
server → **restart it from the Hub Control Panel** if the kernel was installed
while it was running → pick the kernel → run:

```python
import sys, socket
print(sys.prefix)                            # /opt/venv  -> the container
print(open("/etc/os-release").readline())    # ubuntu     -> the container
print(socket.gethostname())                  # nidXXXXXX -- see below
import torch; print(torch.cuda.is_available())   # only if the hub gave you a GPU node
```

`sys.prefix` and `/etc/os-release` are the proof; the hostname is **not** — under
`--network host` it is the node name, because the hostname travels with the
network namespace. Only a default-networked container reports its container ID.

If step 3 passes and step 4 does not, the difference is the hub's environment
rather than the container: check that the `argv[0]` in your `kernel.json` is an
absolute path (the installer bakes one in when run on a login node), and that
the node the hub gave you can see the image —
`perlmutter/helpers/update-image.sh` puts it in the shared store.

---

## B. Your own allocation + ssh tunnel

```bash
cd <your work dir>                       # the notebook starts here
~/idrobolab-env/perlmutter/jobs/interactive_jupyter.sh
```

It allocates a node, starts JupyterLab in the container, and prints the tunnel
line with the node name filled in — the one thing you cannot know in advance.

```
terminal 1 (Perlmutter)                 terminal 2 (laptop)
────────────────────────────            ─────────────────────────────────────
./interactive_jupyter.sh
  requesting: qos=shared_interactive …
  JupyterLab is starting on nid001012:8899
  [check] probing … up to 90 s …
  [check] nid001012:8899 ANSWERS
  …server log, leave it running…
                                        ssh -N -L 8899:nid001012:8899 \
                                            <username>@perlmutter.nersc.gov
                                        browser → http://localhost:8899/lab?token=…
  Ctrl-C when finished
```

Take the **token** from the server log. Ignore the host it advertises — that is
the container ID (`http://53651cfcd19b:8899/…`), because podman gives the
container its own UTS namespace. Use `localhost`.

### Knobs

All are environment variables; trailing arguments go to `jupyter lab`.

| Variable | Default | Notes |
|---|---|---|
| `GPUS` | `1` | `0` for a CPU session (pair with `CONSTRAINT=cpu ACCOUNT=<project>`) |
| `TIME` | `02:00:00` | An idle notebook is charged like a busy one |
| `QOS` | `shared_interactive` | `interactive` for a whole node |
| `PORT` | `8899` | Pick another if it is taken; the launch fails loudly rather than drifting |
| `IMAGE` | `idrobolab` | Short name or full reference; `TAG`/`IMAGE_OWNER` apply to the short form |
| `CPUS` | `32 × GPUS` | Logical cores. The slice QOSes require exactly this |
| `MEM` | unset | **Leave it unset** — see the `--mem` trap below |
| `THREADS` | `CPUS / 2` | Sets `OMP_NUM_THREADS`/`OPENBLAS_NUM_THREADS` |
| `SHM_SIZE` | unset | e.g. `32g`, if dask workers hit shared-memory errors |
| `PUBLISH` | `1` | `0` drops `-p`; the port then will not be reachable |
| `ACCOUNT` | `<project>_g` | `<project>` for CPU work — see [jobs/README.md](../../../perlmutter/jobs/README.md) |

```bash
TIME=00:30:00 ./interactive_jupyter.sh                     # a quick look
QOS=interactive GPUS=4 ./interactive_jupyter.sh            # whole node
IMAGE=otherimage PORT=9101 ./interactive_jupyter.sh
./interactive_jupyter.sh --ServerApp.root_dir=$SCRATCH     # extra jupyter args
```

### The `[check]` lines

A probe runs on the login node and opens a TCP connection to the port on the
compute node — the exact hop `ssh -L` relays through. It reports either way:

```
  [check] nid001012:8899 ANSWERS -- run the ssh -L line now
  [check] NO answer from nid001012:8899 after 90 s -- the tunnel will refuse too
  [check] asking nid001012 what is listening on 8899 ...
```

On failure it asks the compute node directly, via `srun --overlap` into the
live allocation, and prints what `ss -ltn` sees there. A listener visible on
the node but not from the login node is a network block between the two;
no listener at all means the port never reached the node.

### Ctrl-C

Ctrl-C goes to `srun`, not to Jupyter: it asks for a second within one second,
then cancels the step **and the allocation**. That is the intended way to
finish — it frees the slice immediately — but it means there is no graceful
"stop the server, keep the node", and the server is gone the instant you press
it. Run the tunnel from a second terminal. A dropped tunnel does not kill the
server; just re-run the `ssh` line.

---

## Why the launcher looks the way it does

Five things that are not obvious, each of which broke a real session.

**`salloc <command>` runs the command on the login node.** Only `srun` steps
land on the allocated node. `salloc` with *no* command is the case that drops
you onto a compute node; passing a command overrides that. The failure is
silent and charged: the container runs on a shared login node with no GPU while
the allocation sits idle. The giveaway is a hostname reading `loginNN` right
after Slurm said `Nodes nidNNNNNN are ready`.

**Containers need `-p <port>:<port>`.** podman-hpc gives containers a private
network namespace, so binding `0.0.0.0` inside is not enough. Do **not**
conclude otherwise from `/proc/net/dev` showing `hsn0` inside the container —
podman-hpc gives the container a view of the host `/proc`, so `/proc/net`
describes the node, not the namespace. Whether the port answers is the only
reliable test. See [podman-hpc.md](podman-hpc.md), "Networking".

**The container runs as root, and that is correct.** Under rootless podman,
container root *is* your host uid; a non-root user would map into your subuid
range and lose access to `$HOME`, `$SCRATCH` and CFS. Two consequences:
`jupyter lab` refuses to start as uid 0 without `--allow-root`, and `HOME` is
`/root` in the ephemeral overlay unless you pass `-e HOME=$HOME`, which is why
tokens and installed extensions used to vanish every session.

**`shared` is a batch QOS; `shared_interactive` is its interactive twin.**
Same slice, same proportional charge, but a session submitted to `shared`
queues behind regular batch work.

**Never pass `--mem` with `--gpus` on a slice QOS.** Slurm derives a core count
from `--mem` as well as from `--cpus-per-task`, takes the larger, and the GPU
shared queue requires *exactly* 32 logical cores per GPU:

```
salloc: error: Logical queue gpu_shared_ss11 requires you to request 32.0
cores per GPU, job requested 38 cores (adjusted for memory) for 1 GPUs
```

64 GB is 38 cores at the node's 1760 MB per logical core. Ask for the cores;
the ~55 GB per GPU comes with them.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `salloc` sits pending | `QOS=shared` (batch) instead of `shared_interactive` | Ctrl-C; retry, or `QOS=interactive GPUS=4` |
| `Logical queue … requires 32.0 cores per GPU` | `--mem` requested alongside `--gpus` | Unset `MEM` |
| Banner names `loginNN`, not `nidNNNNNN` | payload not wrapped in `srun` | Pull — fixed in the launcher |
| `[C] Running as root is not recommended` then exit | `jupyter lab` refuses uid 0 | `--allow-root` (the launcher passes it) |
| Cookie secret written to `/root/...` | `HOME` not redirected | `-e HOME=$HOME` (the launcher passes it) |
| `[check] NO answer …` + `none` listening | port inside a private namespace | `-p` (the launcher passes it); check `PUBLISH` is not `0` |
| `channel N: open failed: connect failed` | server already gone, or never reachable | Confirm the session is live; read the `[check]` verdict |
| `The port 8899 is already in use` | `--port-retries=0` doing its job | `PORT=9101` |
| `chdir to /global/cfs/…: Permission denied` | supplementary groups dropped | `--group-add keep-groups` (the launcher passes it) |
| `image not known` | image not in the compute-node-visible store | `perlmutter/helpers/update-image.sh idrobolab` on a login node |
| New kernel missing from the hub launcher | hub caches the kernel list | Restart the server from the Hub Control Panel |
| Hub kernel dies with `image not known`, though `podman-hpc images` lists it on a login node | the hub runs no login shell, so `env.sh` never sets `PODMANHPC_ADDITIONAL_STORES` | Source `env.sh`, then re-install with `--force` — the installer bakes the store path into the kernel `env` |
| Container kernel dies at startup | `--network host` may not be accepted | `podman-hpc run --rm --network host <image> true` |
| `IPython parent '/global/homes/…' is not a writable location`, then the kernel never responds | `$HOME` is a symlink (`/global/homes/<i>/<u>` → `/global/u1/<i>/<u>`) and only the resolved name was mounted, so `HOME` itself does not exist in the container | Re-run the installer — it now mounts both spellings. Check `kernel.json`: the `-e HOME=` value must appear as a `-v` destination |

Useful while a session is up:

```bash
squeue --me -o "%i %q %P %T %r"        # QOS, partition, state, pending reason
scontrol show job <jobid>              # everything, including the assigned QOS
ssh nid00XXXX 'ss -ltn | grep 8899'    # is the port on the node at all?
```

---

## Cost

A slice is charged for the fraction of the node it holds, whether or not a cell
is running.

| Session | Charge per wallclock hour |
|---|---|
| 1 GPU, `shared_interactive` (default) | 0.25 GPU node-hour |
| 2 GPUs, `shared_interactive` | 0.5 GPU node-hour |
| Whole node, `interactive` | 1.0 GPU node-hour |
| jupyter.nersc.gov | whatever node the hub allocated, at that QOS |

Keep `TIME` short — restarting is cheap, and a forgotten 4-hour whole-node
session costs four node-hours for nothing.
