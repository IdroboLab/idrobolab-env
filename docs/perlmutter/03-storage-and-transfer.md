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

### rsync / scp (up to about 10 GB)

NERSC suggests scp for files below about 10 GB and Globus above
([NERSC: scp](https://docs.nersc.gov/services/scp/)).
Run these on your **laptop**, with a valid `sshproxy` key. Write the remote path out
in full; on Perlmutter, `echo $SCRATCH` shows yours. rsync and scp use the `nersc-dtn`
alias from your SSH config ([page 1](01-login.md#4-ssh-config)) and need no other
setup.

#### Windows

Windows has no built-in rsync, but its OpenSSH client includes `scp`, which does the same
job for a copy to or from Perlmutter. The commands are the same in Command Prompt and
PowerShell (`-r` copies a folder with everything in it; use paths relative to the
current folder):

```
scp -r mydata nersc-dtn:/pscratch/sd/<x>/<username>/
scp -r nersc-dtn:/global/cfs/cdirs/<project>/projects/<dir>/results .
```

The first line copies the folder `mydata` into your scratch directory; the second creates
`results` in the current folder. (NERSC's scp page suggests the graphical WinSCP for
Windows; the OpenSSH `scp` that comes with Windows works as well.) For rsync, use it
inside WSL (the macOS and Linux instructions below, with the SSH config entries and an
`sshproxy` key in WSL's own `~/.ssh`), or use Globus.

#### macOS and Linux

```bash
# laptop -> Perlmutter scratch
rsync -azPv mydata/ nersc-dtn:/pscratch/sd/<x>/<username>/mydata/

# Perlmutter project dir -> laptop
rsync -azPv nersc-dtn:/global/cfs/cdirs/<project>/projects/<dir>/results/ ./results/
```

`-azPv`: keep times and permissions, compress, resume partial files, show progress.
Re-running the same command copies only what changed. The trailing `/` on the source
means "the contents of"; without it, rsync creates `mydata/mydata`. `scp -r` as above
works here too.

### Globus (large data, many files, or unattended)

NERSC recommends Globus for moving significant amounts of data between NERSC and other
sites ([NERSC: Globus](https://docs.nersc.gov/services/globus/)). If you have not used
Globus before, read the [general Globus page](../03-globus.md) first: it covers the web
app, collections, Globus Connect Personal and the command line. This section is what is
particular to NERSC.

**NERSC's collections.** Search for these names in the File Manager's **Collection**
field:

| Collection | Reaches | NERSC's recommended use |
|---|---|---|
| **NERSC DTN** | CFS, home, common, Perlmutter scratch; **not** HPSS | all transfers into and out of NERSC |
| **NERSC Perlmutter** | the same file systems as NERSC DTN, not HPSS | when NERSC DTN is unavailable |
| **NERSC HPSS** | the HPSS tape archive | transfers into and out of HPSS from other sites |
| **NERSC SHARE** | read-only access to some file systems | the shared Globus collection that guest collections are made on (below) |

There is no separate scratch collection: **NERSC DTN** reaches `$SCRATCH`.

**Signing in.** NERSC's collections can be used by any NERSC user. In the Globus login
page, **NERSC** is one of the organisations in the drop-down list, so you can log in to
Globus with your NERSC account; if you log in with another identity (your university),
link the NERSC identity to your Globus account first
([general page](../03-globus.md#2-log-in)). If NERSC's collection refuses you,
NERSC's tip is to log in to <https://iris.nersc.gov>, which clears authentication
failures.

**Paths to type.** The **Path** field takes the absolute paths of the table at the top of
this page. NERSC's Globus examples use them for scratch and CFS:

| What | Path |
|---|---|
| Scratch | `/pscratch/sd/<x>/<username>/` (`echo $SCRATCH` shows it) |
| Home | `/global/homes/<x>/<username>/` |
| The group's project directory | `/global/cfs/cdirs/<project>/` (yours: `/global/cfs/cdirs/<project>/projects/<dir>/`) |

NERSC's Globus page gives no path examples for home, so if a path does not open, type `/`
into **Path** and click your way down to the folder.

**A first transfer, from a laptop or an instrument PC to CFS.**

1. Install **Globus Connect Personal** on the machine that holds the data, and expose the
   folder you copy from ([general page](../03-globus.md#6-globus-connect-personal)).
   Keep it running. NERSC notes that it is always fastest to use the official NERSC
   collections, and that a Personal collection is for transfers to and from a local
   laptop or computer.
2. At <https://app.globus.org>, open **File Manager**, enter **NERSC DTN** in the
   **Collection** field, sign in, and type `/global/cfs/cdirs/<project>/projects/<dir>/` into
   **Path**.
3. Click **Transfer or Sync to...** and choose your Personal collection in the second
   panel. Select the files in the panel they are in, give the transfer a label, and click
   **Start**. Follow it on **Activity**.

Use **NERSC DTN** to stage input data into `$SCRATCH` before a job, and to take results
out afterwards.

**HPSS through Globus.** The **NERSC HPSS** collection is for transfers between HPSS and
other sites. NERSC warns that Globus transfers involving HPSS with a large number of
files are very slow, cannot resume after an interruption (each network hiccup restarts
the transfer from the beginning), and cannot be split into several streams. Between HPSS
and a NERSC file system (CFS or scratch), use `hsi` and `htar` as described below. For
data that comes from outside, NERSC suggests two stages: Globus to CFS or scratch through
**NERSC DTN**, then `hsi`/`htar` into HPSS, and the reverse to take data out
([NERSC: Globus, section "Globus Transfers and the HPSS Tape Archive"](https://docs.nersc.gov/services/globus/),
[NERSC: archive](https://docs.nersc.gov/filesystems/archive/)).

#### Sharing data with people outside NERSC

NERSC supports sharing through **guest collections** (Globus's *guest collection*, see the
[general page](../03-globus.md#7-sharing-data-with-someone)), with these limits
([NERSC: Globus, section "Sharing Data with Globus"](https://docs.nersc.gov/services/globus/),
[NERSC: sharing](https://docs.nersc.gov/filesystems/sharing/)):

- Guest collections at NERSC are **read-only**: nobody can write into them.
- Only **`/global/cfs/cdirs/<project>/gsharing`** and its subdirectories can be shared. Scratch
  and home cannot.
- The people you share with need a Globus account but **not** a NERSC account.

To share: tell the maintainer (what you share through a guest collection becomes readable, outside
the group, by the people you choose), create the
directory `gsharing` in the project directory, and
[open a ticket](https://help.nersc.gov/) with its path: NERSC has to update its
configuration by hand before that directory can be shared. When NERSC has answered, open the
**NERSC SHARE** collection in Globus, go to its **Collections** tab, choose **Add a Guest
Collection**, and give it a name and a path; most people create a subdirectory of
`gsharing` for each dataset and share that. Click **Create Share**, then choose who may see
it (specific Globus users, or all Globus users).

**Permissions matter.** NERSC warns that files that are world-readable *can be shared by any
NERSC user* once you opt in to Globus sharing. Keep what you put there readable by you and
the group only:

```bash
chmod -R o-rwx /global/cfs/cdirs/<project>/gsharing
```

#### Limits and etiquette

NERSC points to Globus's own limits on the number of files and of pending transfers
(the [general page](../03-globus.md#5-start-a-transfer-and-follow-it) gives the main
one) and publishes none of its own. The data transfer
nodes may be used interactively only for work that prepares data for transfer or is
directly related to it (downloading, `tar`, `gzip`); do not run databases or tests that
saturate a node there, and do not use the very small `/tmp` for data
([NERSC: data transfer nodes](https://docs.nersc.gov/systems/dtn/)).

#### From the command line at NERSC

`module load globus-tools` provides the Globus CLI on Perlmutter, used as described on the
[general page](../03-globus.md#8-the-command-line). The module also has NERSC's helper
scripts; their first use stores a Globus token in
your home directory: never share it, NERSC counts it as your NERSC password
([NERSC: Globus](https://docs.nersc.gov/services/globus/)). NERSC's helper script
`transfer_files.py` copies a list of files; its example, from CFS to Perlmutter scratch,
first writes the list of what to copy (a folder in the list is copied with everything in it):

```bash
module load globus-tools
ls -d /global/cfs/cdirs/<project>/<dir> > transfer.txt
transfer_files.py -s dtn -t perlmutter -d /pscratch/sd/<x>/<username>/input_directory -i transfer.txt
```

`-s` and `-t` name the source and target (`dtn` and `perlmutter` are shortcuts for the
collections above), `-d` is the directory on the target, and `-i` is that list: one full path
per line, of a file or a folder.

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
