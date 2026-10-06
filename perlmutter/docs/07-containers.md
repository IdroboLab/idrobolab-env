# 7. The idrobolab container

A container is a complete, frozen software installation that runs the same way for
everyone. The group image **idrobolab** holds the whole microscopy and simulation
stack, so for most GPU work there is nothing to install.

| | |
|---|---|
| Base | CUDA 12.8, Python 3.12, x86_64 |
| Simulation | abTEM, GPAW (+ gpaw-weaver), ptyrad (ptychography) |
| ML potentials, phonons | fairchem, orb-models (torch 2.8), phonopy, hiphive, pymatgen |
| GPU and parallel | CuPy, dask, dask-cuda (multi-GPU abTEM) |
| Analysis | nionswift, jupyterlab |

Perlmutter runs containers with **podman-hpc** (Docker-compatible). The image is
already in the group's shared image store; `env.sh` ([page 3](03-shell-setup.md))
tells podman-hpc where to find it. Check on a login node:

```bash
podman-hpc images          # should list ghcr.io/<username>/idrobolab   latest
```

**Don't pull the image yourself.** It is 20 GB, and the maintainer refreshes the
shared copy with `helpers/update-image.sh`.

## Batch job

The job templates ([page 5](05-jobs.md#batch-jobs-sbatch)) run `python <your script>`
inside the container:

```bash
sbatch ~/idrobolab-env/perlmutter/jobs/gpu_1gpu_shared.sbatch my_script.py
```

## Interactive shell in the container

On 1 GPU (the usual case), first get a node, then start the container on it:

```bash
salloc -C gpu -q shared_interactive -A <project>_g -t 01:00:00 -n 1 -c 32 --gpus-per-task=1

srun --pty podman-hpc run --rm -it --gpu --group-add keep-groups \
    -v $HOME:$HOME -v $SCRATCH:$SCRATCH -v $CFS:$CFS -e HOME=$HOME \
    --workdir "$PWD" "$IDROBOLAB_IMAGE" bash
```

For a whole node with 4 GPUs,
`~/idrobolab-env/perlmutter/jobs/interactive_gpu.sh` does both steps
([source](../jobs/interactive_gpu.sh)). It always books a full node, even with
`GPUS=1`, so use the commands above for 1–2 GPUs.

What the flags do:

| Flag | Why |
|---|---|
| `--gpu` | makes the GPUs visible inside |
| `--group-add keep-groups` | keeps your <project> group membership. Without it you get `Permission denied` on `/global/cfs/cdirs/<project>` |
| `-v A:A` | podman-hpc mounts **nothing** by default; each folder you read or write must be listed. `$CFS` is `/global/cfs/cdirs` |
| `-e HOME=$HOME` | otherwise `$HOME` points into the container and is lost at exit |
| `--workdir "$PWD"` | start in the current folder (must be inside a mounted path, spelled `/global/cfs/cdirs/...`) |
| `--rm` | delete the container's scratch layer at exit |

Inside, you are `root`, but files you write to mounted folders belong to you. Anything
written outside the mounted folders is gone when you exit.

## Using your own version of a package

abTEM, GPAW and gpaw-weaver are installed from `/opt/src/<name>` inside the image.
Mount your own checkout over that path to use it instead:

```bash
podman-hpc run ... -v $SCRATCH/code/abTEM:/opt/src/abTEM ... "$IDROBOLAB_IMAGE" python script.py
```

Check which copy you got with
`python -c "import abtem; print(abtem.__file__, abtem.__version__)"`. A package
with compiled parts (GPAW) needs to be rebuilt if you change its C code. If you need a
package the image lacks, ask the maintainer to add it to the recipe
(`shared/containers/x86_64-cuda/idrobolab/`).

## Good habits and errors

- **Record the image version with your results.** `latest` moves, so note
  `podman-hpc images --digests | grep idrobolab` alongside every campaign.
- `Permission denied` on a CFS path → `--group-add keep-groups` is missing.
- `workdir ... does not exist on container` → the folder isn't mounted, or you used
  the `/global/cfs/projectdirs/...` spelling (`cd` to the `cdirs` one).
- `locating item named "manifest" ... does not exist` → the shared store's
  permissions broke. Tell the maintainer, and don't follow the message's advice to
  remove the image.
- MPI (GPAW on CPU nodes): use the GPAW templates. They add `--mpi` and
  `GPAW_MPI_BACKEND=cgpaw`, which MPI runs need.

More: [`../podman-hpc.md`](../podman-hpc.md) (written for the sibling `otherimage`
image; the commands are the same) and
[`shared/containers/x86_64-cuda/idrobolab/README.md`](../../shared/containers/x86_64-cuda/idrobolab/README.md).
