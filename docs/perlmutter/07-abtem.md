# 7. abTEM on Perlmutter

abTEM runs its multislice calculations on the GPU through CuPy. There are two ways to
run it here:

| | Container (default) | Your own uv environment |
|---|---|---|
| abTEM, CuPy, dask-cuda, GPAW, … | ready, tested together | you install abTEM and CuPy |
| Use it when | almost always | the container's abTEM (or a package) is not recent enough, e.g. you need a branch or a newer release |
| Several GPUs for **one** calculation | yes (dask-cuda is in the image) | no: run those in the container |

The commands assume your clone of this repository at `~/idrobolab-env` and run on a
login node, unless a comment in the block says otherwise (compute-node shell, or inside
the container). A small example script,
[`abtem_gpu_example.py`](../../perlmutter/examples/abtem/abtem_gpu_example.py), runs a HAADF-type probe
scan of Si on one GPU (`--device cpu` for a CPU test) and writes `haadf.npy` and
`structure.cif`. Use it to try each route before you run your own script.

## Check which abTEM the container has

```bash
# on a login node
podman-hpc run --rm "$IDROBOLAB_IMAGE" python -P -c "import abtem; print(abtem.__version__, abtem.__file__)"
```

The version number alone does not identify the code: it is the same for many commits of
the development branch the image was built from. Note the image digest instead
([page 6](06-containers.md#good-habits-and-errors)).

## Route 1: the container

**Interactively** (1 or 2 GPUs, up to 4 h, charged by the fraction of the node):

```bash
# on a login node
~/idrobolab-env/perlmutter/jobs/interactive_gpu_shared.sh              # 1 GPU, 1 h
GPUS=2 TIME=02:00:00 ~/idrobolab-env/perlmutter/jobs/interactive_gpu_shared.sh
```

You get a shell inside the container on the compute node. Run the example there:

```bash
# inside the container shell
python ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py --out $SCRATCH/abtem-example
exit
```

`exit` ends the session and the charge.

**In a batch job**, from the folder where the log file should go:

```bash
# on a login node
cd $SCRATCH
sbatch ~/idrobolab-env/perlmutter/jobs/gpu_1gpu_shared.sbatch \
    ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py --out $SCRATCH/abtem-example
```

| Template | GPUs |
|---|---|
| `gpu_1gpu_shared.sbatch` | 1, shared queue, 4 h by default (the QOS allows 48 h) |
| `gpu_2gpu_shared.sbatch` | 2, shared queue, 4 h by default |
| `gpu_4gpu_node.sbatch` | 4, a whole node (`gpu_4gpu_hbm80g.sbatch`: the 80 GB nodes) |

**Several GPUs for one calculation.** abTEM starts one dask-cuda worker per visible GPU
when `dask.multi-gpu` is on. Everything that does work must sit under
`if __name__ == "__main__":`, because the workers re-import your script:

```python
import abtem

def main():
    abtem.config.set({"device": "gpu", "dask.multi-gpu": True})
    ...   # build the potential, probe and scan as usual

if __name__ == "__main__":
    main()
```

Submit it with `gpu_2gpu_shared.sbatch` (2 GPUs) or `gpu_4gpu_node.sbatch` (4 GPUs). On
4 GPUs a frozen-phonon HAADF benchmark ran faster than on 1
([`verification/multigpu_abtem/`](../../perlmutter/verification/multigpu_abtem/)).

**Your own abTEM branch** replaces the image's copy when you mount a checkout over
`/opt/src/abTEM` ([page 6](06-containers.md#using-your-own-version-of-a-package)).
For a batch job, copy the template, uncomment its
`MOUNTS="$MOUNTS -v $SCRATCH/code/abTEM:/opt/src/abTEM"` line and point it at your
checkout:

```bash
# on a login node
cp ~/idrobolab-env/perlmutter/jobs/gpu_1gpu_shared.sbatch $SCRATCH/my_job.sbatch
```

Print `abtem.__file__` in your script (it must start with the checkout's path inside
`/opt/src/abTEM`) and record the commit: `git -C $SCRATCH/code/abTEM rev-parse HEAD`.

## Route 2: your own uv environment

Create it once, **on a login node** (compute nodes should not download anything). It
uses Python 3.13, the interpreter in the group's uv folder. CuPy here is version 14,
newer than the container's 13.5.1; its `[ctk]` extra installs the CUDA 12.8 libraries
as wheels, which CuPy finds on its own. The requirements are in the example script's
header, and installing from the script pulls in all of them:

```bash
# on a login node
uv venv --python 3.13 ~/venvs/abtem
uv pip install -p ~/venvs/abtem -r ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py
```

That also installs the PyPI release of abTEM. To use your own checkout (a branch you
work on) instead, replace it:

```bash
# on a login node
git clone https://github.com/abTEM/abTEM ~/code/abTEM
uv pip install -p ~/venvs/abtem -e ~/code/abTEM
```

Compare before you choose: on 2026-10-06 the PyPI release was abTEM 1.0.10, older than
the 1.1.0 development version in the container. The environment lives in `$HOME`
([page 5](05-python-uv.md#where-environments-live)).

The first GPU run shows whether the libraries are in order: the example prints the
abTEM and CuPy versions and the CUDA runtime and driver versions before it computes.

**Interactively:**

```bash
# on a login node; the shell that salloc gives you is on the compute node
salloc -C gpu -q shared_interactive -A <project>_g -t 01:00:00 -n 1 -c 32 --gpus-per-task=1 -L scratch
srun ~/venvs/abtem/bin/python ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py --out $SCRATCH/abtem-example
exit
```

**In a batch job:**

```bash
# on a login node
cd $SCRATCH
sbatch ~/idrobolab-env/perlmutter/jobs/abtem_uv_gpu_shared.sbatch \
    ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py --out $SCRATCH/abtem-example
sbatch --gpus=2 --cpus-per-task=64 ~/idrobolab-env/perlmutter/jobs/abtem_uv_gpu_shared.sbatch my_script.py
sbatch ~/idrobolab-env/perlmutter/jobs/abtem_uv_gpu_node.sbatch ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py
```

The first runs the example on 1 GPU. The second is a script of your own on 2 GPUs (the
process sees both; the example uses one). The third books a whole node and runs four
independent single-GPU copies of the script, one per GPU, as a four-point sweep
(electron energies 60, 100, 150 and 200 keV for the example; edit the `srun` line of a
copy for your own parameters). The job scripts run `~/venvs/abtem/bin/python`; `VENV=<path> sbatch ...`
selects another environment.

## Good habits

- **Shared queue unless all 4 GPUs are busy.** 1 or 2 GPUs on `shared` cost a quarter or
  half of a node; a whole node costs four times a single GPU
  ([page 4](04-jobs.md#accounts-and-cost)).
- **Write results to `$SCRATCH`**, then copy what you keep to CFS: scratch is purged after
  8 weeks ([page 3](03-storage-and-transfer.md)).
- **Record what produced a result.** Container: `podman-hpc images --digests | grep
  idrobolab` and the abTEM checkout's commit if you mounted one. uv environment: the
  abTEM commit (`git -C ~/code/abTEM rev-parse HEAD`) or version, and
  `uv pip freeze -p ~/venvs/abtem > $SCRATCH/abtem-example/requirements.txt` next to the
  results.
