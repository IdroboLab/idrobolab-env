# 3. Where data goes, and moving it

## The file systems

Every file system below is visible from login nodes, compute nodes, the data transfer
nodes and Globus. One row per file system. Sizes are NERSC defaults: per user for home
and scratch, shared by the whole group for CFS and common.

| Name | Path | Size | Safety net | Use it for |
|---|---|---|---|---|
| Home | `$HOME` = `/global/homes/<x>/<username>` | 40 GB, 1 M files | snapshots, backed up | code, scripts, configs, small personal environments |
| Scratch | `$SCRATCH` = `/pscratch/sd/<x>/<username>` | 20 TB, 10 M files | **none: purged** | job input and output, anything large and temporary |
| Project (CFS) | `/global/cfs/cdirs/<project>` | group quota | snapshots | results you keep, data you share with the group |
| Software | `/global/common/software/<project>` | 10 GB, 1 M files (group) | none | installed software and group environments; **read-only on compute nodes** |
| Tape (HPSS) | via `hsi` / `htar` | per allocation | — | archiving finished campaigns |

`<x>` is the first letter of your username.

- **Scratch purge:** files on `$SCRATCH` that nobody has read for **8 weeks** are
  deleted. NERSC lists upcoming candidates in `$SCRATCH/.purge/`, but don't rely on
  noticing: never keep the only copy of anything there.
- **Where your work goes:** run in `$SCRATCH`, copy what you want to keep to CFS, and
  archive finished projects to HPSS. Group work lives under
  `/global/cfs/cdirs/<project>/projects/` (the `cdp` alias goes there). Make a folder for
  your project or your name.
- **Sharing:** files on CFS must be group-readable for colleagues to see them. If
  someone can't read your folder, run `chmod -R g+rX <folder>`.
- Always write CFS paths as `/global/cfs/cdirs/...`, not `/global/cfs/projectdirs/...`.
  It is the same directory, but containers only see the `cdirs` name.

## Checking usage

| What | Command |
|---|---|
| Usage and quota of the file systems you use | `showquota` (login and transfer nodes only) |
| Size of one folder | `du -sh <folder>` (slow on huge trees, so point it at a subfolder) |
| CFS usage, graphically | <https://iris.nersc.gov/utils/datadash> |

## Moving data in and out

**Never move data through the login nodes** (`perlmutter`): NERSC kills long-running
transfers there. Use the data transfer nodes (`nersc-dtn` from
[page 1](01-login.md#4-ssh-config)) or Globus.

### rsync / scp (up to a few tens of GB)

Run these on your **laptop**, with a valid `sshproxy` key. Write the remote path out
in full; on Perlmutter, `echo $SCRATCH` shows yours.

```bash
# laptop -> Perlmutter scratch
rsync -azPv mydata/ nersc-dtn:/pscratch/sd/<x>/<username>/mydata/

# Perlmutter project dir -> laptop
rsync -azPv nersc-dtn:/global/cfs/cdirs/<project>/projects/<dir>/results/ ./results/
```

`-azPv`: keep times and permissions, compress, resume partial files, show progress.
Re-running the same command copies only what changed. The trailing `/` on the source
means "the contents of"; without it, rsync creates `mydata/mydata`.

**Windows has no built-in rsync.** Use `scp` in PowerShell instead
(`scp -r mydata nersc-dtn:/pscratch/sd/<x>/<username>/`), or rsync inside WSL, or
Globus.

### Globus (large data, many files, or unattended)

Globus copies in the background, retries on failure and emails you when it's done.

1. Log in at <https://app.globus.org>.
2. Choose the collection **NERSC DTN** (all NERSC file systems except HPSS). It asks
   for your NERSC login.
3. On the other side, choose your university's collection, or install
   **Globus Connect Personal** on your laptop or instrument PC to make it a
   collection.
4. Pick folders on both sides and click **Start**.

### HPSS tape archive

Bundle data into large archives. HPSS handles many small files badly.

```bash
htar -cvf myproject_2026.tar myproject/     # directory -> one tar on HPSS
hsi ls                                      # list your HPSS home
htar -xvf myproject_2026.tar                # restore into the current directory
```

### From the internet

Login and transfer nodes have internet access: `wget`, `curl`, `git clone`, `uv` and
container pulls all work there. Download big files on `nersc-dtn`.
