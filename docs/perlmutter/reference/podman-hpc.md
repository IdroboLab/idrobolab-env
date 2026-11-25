# idrobolab container for NERSC Perlmutter

OCI (Docker-format) image with a curated GPAW, abTEM and microscopy-analysis
stack for Perlmutter's GPU nodes, consumed with **podman-hpc**
(NERSC's recommended container runtime; Apptainer SIF images are not
supported at NERSC).

This is the idrobolab recipe (`shared/containers/x86_64-cuda/idrobolab/`) as a
Dockerfile. **Status: built and published.** `ghcr.io/idrobolab/idrobolab` exists and is
public, and has been pulled on Perlmutter (`shared/containers/x86_64-cuda/idrobolab/README.md`,
Status).

## Fit to Perlmutter

- **CPU/GPU**: AMD Milan + A100 (sm_80) — covered by the `-march=x86-64-v3`
  CPU code and the fat cu129/cuda12 wheels (torch 2.13.0, cupy).
- **MPI**: stock MPICH 4.3.2 built from source with shared libraries —
  exactly NERSC's documented recommendation, so `podman-hpc run --mpi` can
  swap in the ABI-compatible (`libmpi.so.12`), Slingshot-optimized Cray
  MPICH at runtime. Without `--mpi`, the container's own MPICH still works
  (TCP transport).

## Contents

| File | Purpose |
|---|---|
| `Dockerfile` | OCI image recipe (base: NGC `nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04`) |
| `requirements-idrobolab.txt` | Curated Python stack — hand-maintained |
| `siteconfig.py` | GPAW build configuration (MPI, ScaLAPACK, FFTW, libxc, libvdwxc) |
| `prepare_build_context.sh` | Stages the three source trees into `./src/` |

The three dev packages (**gpaw**, **gpaw-weaver**, **abTEM**, each staged from
the committed tree of the commit that `sources.txt` names, by `prepare_build_context.sh`)
are installed **editable** at `/opt/src/<name>`;
mount a cluster checkout over that path to run any branch. PAW datasets come
from the `gpaw-data` pip package inside the image.

## Build

Members do not build the image: it is built and pushed from the maintainer's
devcontainer with `publish.sh`, as described under "Build & run" in
[`shared/containers/x86_64-cuda/idrobolab/README.md`](../../../shared/containers/x86_64-cuda/idrobolab/README.md).
The maintainer pulls it into the group's shared store with
`perlmutter/helpers/update-image.sh`.

## Image storage

podman-hpc keeps **two** stores, which is what makes `migrate` necessary:

| Store | Contents | Visible to compute nodes |
|---|---|---|
| local (graphroot) | ordinary podman layer store — what `build` and `pull` write first | no, login-node-local |
| squash store | each image flattened to one squashfs file | **yes** — this is the one jobs read |

`pull` populates both automatically; `build` populates only the local store,
hence `podman-hpc migrate <tag>`. `podman-hpc images` lists both copies, the
squashed one flagged read-only.

A job reads squashed images from two directories: podman-hpc's default squash directory,
`$SCRATCH/storage` (where a plain `podman-hpc pull` puts the squashed image), and the
group's shared store on CFS, which `env.sh` adds through
`PODMANHPC_ADDITIONAL_STORES`. `update-image.sh` puts released tags into the shared store
and dev builds and release candidates (`dev`, `<N>-rc`) into `$SCRATCH/storage`. Tags are
kept per store: a plain `podman-hpc pull` migrates into `$SCRATCH/storage`, and a copy
left there keeps its tag after a newer image under the same tag lands in the shared
store. `podman-hpc images` then lists two digests for the tag, and podman may run either
image. `update-image.sh` stops in that case.
Remove the unwanted copy by tag, in the store that holds it (`rmsqi` does not take an
image ID):

```bash
podman-hpc --squash-dir "$SCRATCH/storage" rmsqi ghcr.io/idrobolab/idrobolab:dev
```

A listing made with `--squash-dir` does not show which store holds a copy. With
`env.sh` sourced, `podman-hpc --squash-dir <dir> images` also lists the store in
`PODMANHPC_ADDITIONAL_STORES` (the `/dvs_ro` mirror of `$PODMAN_STORE`): an image
the shared store holds shows up in a listing made with `--squash-dir
"$SCRATCH/storage"` too, and a listing made with `--squash-dir "$PODMAN_STORE"`
shows each image the shared store holds twice, once per path to the same
directory. Emptying the variable does not narrow the listing; `images` then fails
with

```
Error: configure storage: overlay: image path "." is not absolute.  Can not be relative
```

To remove a squashed copy without knowing its store, run `rmsqi` in each:

```bash
for s in "$SCRATCH/storage" "$PODMAN_STORE"; do
    podman-hpc --squash-dir "$s" rmsqi <image>:<tag>
done
```

`rmsqi` acts on the `--squash-dir` store only. It prints nothing when it removes
the copy and `ERROR:root:Image <image>:<tag> not found` when that store has none.
`podman-hpc rmi` needs a local-store copy: given an image ID that exists only
squashed, it answers `image not known`.

Upstream defaults are `graph_root=/tmp/{uid}_hpc/storage` and
`run_root=/tmp/{uid}_hpc`; NERSC overrides them site-wide — a Perlmutter login
node was observed using `/images/<uid>_hpc/storage`, node-local space that NERSC
provisions for this. **Leave both unset.** Pointing the graph root at `$SCRATCH`
or CFS lets the pull succeed and the squash fail every time (see the block in
`env.sh`). Print the values
actually in force rather than trusting either:

```bash
podman-hpc --help | grep -A2 squash-dir     # resolved squash-dir default
podman-hpc info | grep -iE "graphroot|runroot"
```

Both are customisable. The flag is per-invocation and goes **before** the
subcommand; everything else is an env var named after the config key,
uppercased and prefixed (`graph_root` -> `PODMANHPC_GRAPH_ROOT`):

```bash
podman-hpc --squash-dir /global/cfs/cdirs/<project>/shared_images pull <image>

export PODMANHPC_GRAPH_ROOT=$SCRATCH/podman/storage
export PODMANHPC_RUN_ROOT=$SCRATCH/podman/run
export PODMANHPC_ADDITIONAL_STORES=/global/cfs/cdirs/<project>/shared_images
```

Precedence, lowest to highest: built-in defaults, config-file template, env
template, `podman_hpc.conf`, environment variables.

Three things that bite in practice:

- **`$SCRATCH` is purged after 8 weeks without access — squashed images
  included.** If the site squash dir sits under `$SCRATCH` (it does by
  default), an image pulled for a long campaign can vanish between runs and
  the failure shows up at job time, not pull time. Put campaign images on CFS
  with `--squash-dir` and record the digest alongside the results.
- **Read a CFS squash dir through the DVS read-only mount** — point
  `PODMANHPC_ADDITIONAL_STORES` at `/dvs_ro/...` rather than
  `/global/cfs/...` for faster container startup on compute nodes.
- **Watch `$HOME` if the local store lives there.** `~/.local/share/containers`
  against the 40 GB home quota fills quickly with a CUDA image this size, and
  there is no purge policy on the local build store — it only grows.

### Supplementary groups are dropped in the container

podman runs rootless in a user namespace and maps only your **primary** group.
Every supplementary group is dropped inside the container — and on NERSC,
supplementary group membership is how access to `/global/cfs/cdirs/<project>`
is granted. The symptom is a path your shell is sitting in that the container
cannot enter:

```
Error: crun: chdir to `/global/cfs/cdirs/<project>/projects/<name>`: Permission denied
srun: error: nid001008: task 0: Exited with exit code 126
```

It is easy to misread as a per-user permission problem, because it bites
collaborators for whom the project group is supplementary while working fine for
whoever has it as their primary group — no amount of `chmod` will help, since
the container is not presenting the group at all.

**Confirmed on Perlmutter 2026-08-19**: adding `--group-add keep-groups` (crun
only, rootless only) resolved it for a collaborator who could not enter a
project directory their own shell was sitting in. Every launcher here passes it;
`PODMAN_GROUP_FLAGS=` disables it.

To diagnose it directly, compare group membership across the boundary:

```bash
id                                                     # on the host
podman-hpc run --rm -v /global/cfs/cdirs:/global/cfs/cdirs <image> id
```

Fewer groups inside than outside is the signature.

### Sharing a store: permissions

A store on CFS is only usable by the project if its files are group-readable,
and `umask` does not achieve that on its own. containers/storage sets explicit
modes on some metadata — the per-image directory and its `manifest` above all —
so those land `0700` regardless, while everything around them is `0775`/`0664`.
A collaborator then reads `images.json`, learns the image ID, and hits

```
Error: locating item named "manifest" for image with ID <id>
       (consider removing the image to resolve the issue): file does not exist
```

which looks like a corrupt store but is a permission problem; podman responds by
re-downloading the image. **Do not follow the "consider removing the image"
advice** — it deletes a good multi-GB image to work around a `chmod`.

A default ACL cannot prevent this: a POSIX default ACL masks the mode a process
*requests* at creation and cannot grant more than was asked for, so a process
that explicitly creates `0700` still gets `0700`. The permissions have to be
re-applied after whatever wrote the store:

```bash
~/idrobolab-env/perlmutter/helpers/fix-store-perms.sh           # fix $PODMAN_STORE and verify
~/idrobolab-env/perlmutter/helpers/fix-store-perms.sh --check   # report only; exit 1 if broken (cron-safe)
```

`update-image.sh` calls it after every pull, so the normal workflow stays
correct on its own. Run it by hand after a direct `podman-hpc pull --squash-dir`,
or when a collaborator has pulled into the shared store themselves.

Cleanup: `podman-hpc rmi <image>` drops both copies of an image that has a local copy
(one held only squashed needs `rmsqi`, above); deleting
`$SCRATCH/storage` and `~/.local/share/containers` is NERSC's reset for a
wedged store.

## Run on Perlmutter

```bash
# GPU, single node
podman-hpc run --rm --gpu "$IDROBOLAB_IMAGE" python script.py

# GPAW, MPI across nodes — --mpi injects the host Cray MPICH (MPICH ABI)
srun -N 4 --ntasks-per-node=64 \
    podman-hpc run --rm --mpi "$IDROBOLAB_IMAGE" python gpaw_script.py

# Hybrid MPI+OpenMP (OMP_NUM_THREADS defaults to 1 in the image)
srun -N 2 --ntasks-per-node=16 -c 8 \
    podman-hpc run --rm --mpi -e OMP_NUM_THREADS=8 \
    "$IDROBOLAB_IMAGE" python gpaw_script.py
```

These examples mount nothing, so they touch only the image store: run them in an allocation
that declares `-L cfs` ([page 4](../04-jobs.md#file-system-licenses)).

Check the current NERSC podman-hpc docs for the exact `--mpi`/`--gpu` flag
names and srun integration — these follow NERSC's documented patterns but
may evolve.

## Networking

**A server inside the container needs `-p <port>:<port>` to be reachable from
the node, exactly as with Docker on a laptop.** Confirmed 2026-08-27: a
JupyterLab bound to `0.0.0.0:8899` in the container was unreachable — refused
from a login node, refused over `ssh -J` on the compute node itself, and absent
from `ss -ltn` there — and adding `-p 8899:8899` (the only change) made it work.

**Do not conclude host networking from `/proc/net/dev`.** This is the trap that
cost several debugging rounds, because the container looks like it is on the
host network:

```bash
$ podman-hpc run --rm ghcr.io/idrobolab/idrobolab:latest sh -c 'hostname; cat /proc/net/dev'
04ad5a40ad5c
Inter-|   Receive ...
    lo: ...
  hsn0:   30884     514 ...
```

`hsn0` — the node's Slingshot interface, with live counters — appears inside
the container, where a private namespace would be expected to show only `lo`
plus a `10.0.2.x` slirp4netns tap. It is not evidence of the namespace:
podman-hpc gives the container a view of the host `/proc`, so `/proc/net/*`
describes the node, not the container. The only reliable test is whether the
port actually answers:

```bash
# on a compute node, in the container
podman-hpc run --rm -p 8899:8899 <image> python3 -m http.server 8899 --bind 0.0.0.0
# second shell, SAME node, while that is running
ss -ltn | grep 8899
curl -sI http://localhost:8899/
```

`perlmutter/jobs/interactive_jupyter.sh` runs that check automatically when its
reachability probe fails, via `srun --overlap` into the live allocation; see
`jupyter.md` for the whole story.

**`--network host` is accepted and works**, verified on a compute node
2026-08-27: with it, a server bound inside the container appears in `ss -ltn`
on the node with no `-p` at all. Use it where per-launch ports rule out `-p` —
a Jupyter *kernel*, for instance, whose five ZMQ ports are chosen at start-up
(`perlmutter/helpers/install-jupyter-kernel.sh`). For a single known port, `-p` is the
narrower tool and is what `perlmutter/jobs/interactive_jupyter.sh` uses.

MPI is unaffected by any of this — `podman-hpc run --mpi` handles rank
rendezvous itself, and needs no published ports.

**Mount paths under the name you will use, not just the resolved one.** `$HOME`
on Perlmutter is `/global/homes/<i>/<user>`, a symlink to
`/global/u1/<i>/<user>`. Mounting only the resolved path leaves `$HOME` itself
non-existent inside the container, which surfaces as *"not a writable
location"* from anything that resolves `~`, and quietly sends writes into the
ephemeral overlay. `-v "$HOME:$HOME"` works because podman resolves the source
symlink but creates the destination exactly as given. The `add_mount` helper in
`perlmutter/jobs/*` and `perlmutter/helpers/install-jupyter-kernel.sh` mounts both spellings.

Two consequences of running as root worth knowing:

- **The hostname inside a default-networked container is the container ID**
  (`04ad5a40ad5c` above), not `nidXXXXXX`. Anything that advertises its own URL
  — Jupyter, a dask dashboard — prints that ID as the host; substitute the real
  node name (`echo $SLURM_NODELIST`, or `hostname` outside the container).
  Under `--network host` the hostname is the node name instead, since it
  travels with the network namespace (observed 2026-08-27: `nid004142` from a
  hub kernel). So the hostname tells you the network mode, not whether you are
  in a container — use `sys.prefix` or `/etc/os-release` for that.
- **A port you open is reachable by anyone who can route to the node.** Keep
  whatever token or auth the server offers.

Reaching such a port from your laptop is an ssh problem, not a container one —
the tunnel crosses login node → compute node, a boundary the container never
sees:

```bash
# laptop; the far end must be the node name, not localhost, because it is
# resolved on the login node
ssh -N -L 8899:nidXXXXXX:8899 <user>@perlmutter.nersc.gov
```

`perlmutter/jobs/interactive_jupyter.sh` does the whole sequence and prints that line
with the node filled in.

## The container runs as root, and that is correct here

`whoami` inside the container says `root`. Under **rootless** podman that root
is your own host uid: the user namespace maps container uid 0 to the uid that
launched it. Files the container writes to a mounted path come out owned by
you, not by root, and the container has no privilege on the node it did not
already have.

So do **not** add a non-root user to these images. It would make things worse:
a non-root container uid maps into your *subuid* range (something like
100999), which does not own your `$HOME`, `$SCRATCH` or the project directory —
the container would lose write access to every mounted path.

Two consequences do need handling:

- **`HOME` is `/root`**, which lives in the container's ephemeral overlay and
  disappears with `--rm`. Anything a tool stores in its home — Jupyter tokens,
  kernels, installed extensions, matplotlib's font cache — is lost each run.
  Pass `-e HOME="$HOME"` (with `$HOME` mounted) to keep that state.
- **Some tools refuse to run as uid 0.** `jupyter lab` is one: it prints
  `[C] Running as root is not recommended. Use --allow-root to bypass.` and
  *exits*. `--allow-root` is required, not cosmetic.

`--group-add keep-groups` is the related flag: it passes your supplementary
groups through, which is how project access to `/global/cfs/cdirs/<project>`
is granted. See "Supplementary groups are dropped in the container" above.

## Running your own branches (cluster checkouts)

The idrobolab image installs gpaw, gpaw-weaver and abTEM **editable** at
`/opt/src/<name>`, so mount a checkout over that path:

```bash
cd $SCRATCH/code
git clone https://gitlab.com/gpaw/gpaw.git && git -C gpaw checkout <branch>

podman-hpc run --rm --gpu \
    -v $SCRATCH/code/gpaw:/opt/src/gpaw \
    "$IDROBOLAB_IMAGE" python script.py
```

Mount only the repos you want to override. gpaw-weaver and abTEM are pure
Python — any branch just works. For **gpaw**, the compiled `_gpaw.so` stashed
in site-packages serves clones without one, so a branch that changes only
Python files works too. The image is a slim runtime without compilers or the
GPAW build configuration, so a branch that changes the C sources cannot be
rebuilt inside it; that needs a new image from the idrobolab recipe.

## Notes and caveats

- **torch cu129**: if `download.pytorch.org/whl/cu129` no longer carries the
  pinned version, switch the index to a CUDA variant that does (any 12.x
  variant covers sm_80).
- **nvalchemi-toolkit-ops** is installed best-effort; on failure the build
  continues and orb-models uses its pure-torch path.
- **PAW datasets**: `gpaw-data` is auto-discovered by GPAW 25.x; fallback
  `GPAW_SETUP_PATH=/opt/venv/lib/python3.12/site-packages/gpaw_data/setups`.
- Custom core-hole setups generated at runtime should live in a mounted
  host directory; add it to `gpaw.setup_paths` in the script as usual.
