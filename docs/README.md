# Documentation

Documentation for members of the IdroboLab group: a step-by-step introduction for NERSC
Perlmutter (project **<project>**), written for people with little git, SSH or HPC experience,
and a page for NCSA Delta. Work through the pages in order; each builds on the ones before.
Everything lives in the group repository
[IdroboLab/idrobolab-env](https://github.com/IdroboLab/idrobolab-env).

## General pages

They apply on any machine, not only on Perlmutter.

| # | Page | What you set up or learn |
|---|---|---|
| 1 | [GitHub: account and SSH key](01-github.md) | GitHub account with two-factor authentication, the IdroboLab organisation, an SSH key, the `~/.ssh/config` entry for github.com, the SSH agent, git's one-time settings |
| 2 | [Cloning repositories](02-cloning.md) | clone the group's, your own and public repositories, keep a clone up to date, everyday git, your own projects in git and data out of it |
| 3 | [Globus](03-globus.md) | log in, collections, the File Manager, transfers and Activity, Globus Connect Personal, sharing, the command line |

[Contributing](CONTRIBUTING.md) explains how to propose a change to this repository
(every change reaches `main` through a pull request).

## Perlmutter

The [Perlmutter section](perlmutter/README.md) takes a new member from the NERSC account
to running jobs, Python, the group container, Jupyter, Nion Swift and coding agents (ten
numbered pages, a table of what each covers, and the everyday commands). It follows the
general pages: [Perlmutter page 2](perlmutter/02-shell-setup.md) uses the GitHub access from
general page 1, and [Perlmutter page 3](perlmutter/03-storage-and-transfer.md) is the
NERSC-specific counterpart of general page 3. Start at
[Perlmutter page 1](perlmutter/01-login.md) once you have done the general pages.

Alongside the pages, [`perlmutter/reference/`](perlmutter/reference/) holds the long
reference notes ([Jupyter](perlmutter/reference/jupyter.md),
[podman-hpc](perlmutter/reference/podman-hpc.md),
[Nion Swift over ThinLinc](perlmutter/reference/nionswift-perlmutter-thinlinc.md),
[NERSC's filesystem guard](perlmutter/reference/nersc-filesystem-guard.md)), and
[group conventions](perlmutter/conventions.md) and [Codex](perlmutter/codex.md) are there too.

## Delta

The [Delta page](delta/README.md) covers NCSA's Delta system: accounts and charging, getting
the container image with `delta/get-image.sh`, the job templates per partition in
[`delta/jobs/`](../delta/jobs/README.md) (partition matrix, how MPI is launched, a first-run
checklist), the multi-GPU abTEM verification, and the conventions that avoid Delta's
common traps. It is one page rather than a numbered series: the general pages above (GitHub,
cloning) apply on Delta as they do on Perlmutter.
