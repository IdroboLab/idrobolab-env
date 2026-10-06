# 8. Jupyter

There are two ways to run notebooks on Perlmutter, and they complement each other:

| | A. jupyter.nersc.gov | B. Your own node + tunnel |
|---|---|---|
| Good for | day-to-day analysis | reproducing or debugging a batch job |
| Setup | register a kernel once | nothing |
| Survives a closed laptop | yes | no: closing the terminal that started it ends the session |

## A. jupyter.nersc.gov

1. Go to <https://jupyter.nersc.gov> and log in with password+OTP.
2. Start a server on Perlmutter. A **login node** server costs nothing and is fine
   for light work. A compute or GPU node server is charged to the allocation like any
   job; pick a GPU node to use the GPU kernel below.
3. Pick a kernel in the launcher.

**Kernels.** The group setup ([page 3](03-shell-setup.md#2-group-environment))
linked any shared group kernels into your account. To add your own uv
environment ([page 6](06-python-uv.md)), on a login node:

```bash
uv pip install -p ~/venvs/analysis ipykernel           # the env needs ipykernel
~/idrobolab-env/perlmutter/helpers/install-jupyter-kernel.sh \
    --venv ~/venvs/analysis --name analysis --display "Analysis (venv)"
```

To add a kernel that runs in the group container (if the shared kernels don't already
include one):

```bash
~/idrobolab-env/perlmutter/helpers/install-jupyter-kernel.sh \
    --image idrobolab --name idrobolab --display "idrobolab (GPU)" --gpu
```

The script's `--list` option lists your kernels and `--remove <name>` deletes one. A
new kernel only appears after you restart your server
(File → Hub Control Panel → Stop My Server, then start it again).

## B. JupyterLab on a node you book yourself

This runs the same container image the batch jobs use, on 1 GPU, for 2 hours by
default:

```bash
cd /global/cfs/cdirs/<project>/projects/<dir>      # notebooks start here
~/idrobolab-env/perlmutter/jobs/interactive_jupyter.sh
```

When the server is up, the script prints an `ssh -L` line naming the node. Run that
line in a second terminal **on your laptop**, using your `perlmutter` alias, e.g.
`ssh -N -L 8899:nid001012:8899 perlmutter`. Then open the
`http://localhost:8899/lab?token=...` address from the server log in your browser.

- Options are set as variables in front of the command: `TIME=00:30:00`, `GPUS=2`,
  and for a CPU node `GPUS=0 CONSTRAINT=cpu ACCOUNT=<project>`.
- **Ctrl-C twice** (quickly) in the first terminal ends the server *and* the
  allocation. A dropped
  tunnel doesn't: just re-run the `ssh -L` line.
- The allocation is charged while the notebook sits idle, so stop it when you're done.

Details and troubleshooting: [`../jupyter.md`](../jupyter.md).
