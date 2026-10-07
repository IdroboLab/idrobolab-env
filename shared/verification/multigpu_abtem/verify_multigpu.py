#!/usr/bin/env python
"""Verify that abTEM distributes GPU work across every GPU on a node.

Cluster-agnostic: this payload is shared by the Delta and Perlmutter launchers
(the multigpu_abtem directories under delta/ and perlmutter/) and runs on any
multi-GPU box with CuPy + dask-cuda. Delta offers 4-, 8- and H200x8 GPU nodes; Perlmutter
GPU nodes are 4x A100 only, so GPU-count sweeps there top out at 4. It exercises the multi-GPU
support added on the abTEM ``multi-gpu-support`` branch, which routes lazy GPU
computes through a dask-cuda cluster (one worker process per GPU).

What it checks, in order:

  0. Environment      -- CuPy / dask / dask-cuda / abTEM versions, visible GPUs,
                         and whether the running abTEM actually has the multi-GPU
                         code (older abTEM always forces the synchronous scheduler
                         on GPU and cannot use a cluster).
  1. Cluster bring-up -- a dask_cuda.LocalCUDACluster with one single-threaded
                         worker per visible GPU; abtem.is_gpu_dask_client accepts it.
  2. GPU coverage     -- every worker is pinned to a *distinct* physical GPU
                         (distinct PCI addresses) and can run a CuPy kernel.
  3. abTEM (explicit) -- a frozen-phonon exit-wave simulation (one independent
                         chunk per configuration) computed with the cluster active;
                         the dask task stream must show work on *all* GPU workers.
  4. abTEM (automatic)-- the same, but driven purely by ``config['dask.multi-gpu']``
                         with no pre-existing client, so abTEM starts the cluster
                         itself -- the "automatically use all GPUs" headline path.
  5. Timing (optional)-- wall-clock for 1 GPU vs N GPUs on the same workload.

If dask-cuda is missing (or ``--no-cluster`` is given) it degrades to a per-device
fallback that confirms each GPU can independently run abTEM -- useful, but NOT a
test of distribution. Exit status is non-zero if any check FAILs.

Usage (inside the container, on a GPU node):

    # Delta (Apptainer):
    apptainer exec --nv $SIF python verify_multigpu.py            # auto-size to visible GPUs
    apptainer exec --nv $SIF python verify_multigpu.py --gpus 4 --timing
    # Perlmutter (podman-hpc):
    podman-hpc run --rm --gpu -v $PWD:$PWD $IMAGE \
        python verify_multigpu.py --no-cluster   # per-GPU smoke test only

See README.md for how to provide a dask-cuda / dask stack that matches the
container (the versions deadlock, and this is the crux of getting it running).
"""

from __future__ import annotations

import argparse
import importlib
import os
import socket
import sys
import time
import traceback
from contextlib import contextmanager

# ---------------------------------------------------------------------------
# tiny result tracker + reporting helpers
# ---------------------------------------------------------------------------

RESULTS: list[tuple[str, str, str]] = []  # (name, status in {PASS,WARN,FAIL,SKIP}, detail)


def record(name: str, status: str, detail: str = "") -> None:
    RESULTS.append((name, status, detail))
    marker = {"PASS": "[ PASS ]", "WARN": "[ WARN ]", "FAIL": "[ FAIL ]", "SKIP": "[ SKIP ]"}[status]
    line = f"{marker} {name}"
    if detail:
        line += f" -- {detail}"
    print(line, flush=True)


def section(title: str) -> None:
    print("\n" + "=" * 78, flush=True)
    print(title, flush=True)
    print("=" * 78, flush=True)


@contextmanager
def guard(name: str):
    """Turn an unexpected exception inside a check into a FAIL instead of a crash."""
    try:
        yield
    except Exception as exc:  # noqa: BLE001 -- verification must not abort on one check
        record(name, "FAIL", f"{type(exc).__name__}: {exc}")
        traceback.print_exc()


# ---------------------------------------------------------------------------
# worker-side helpers (must be importable/pickled into dask workers -> top level)
# ---------------------------------------------------------------------------


def _gpu_pci_address() -> str:
    """PCI address of the CuPy current device -- unique per physical GPU on a node.

    dask-cuda pins each worker to one GPU via CUDA_VISIBLE_DEVICES, so within a
    worker the "current" device (ordinal 0) is a distinct physical GPU. PCI ids
    are the driver's physical view and are not remapped by CUDA_VISIBLE_DEVICES.
    """
    import cupy

    dev = cupy.cuda.runtime.getDevice()
    p = cupy.cuda.runtime.getDeviceProperties(dev)
    return "%04x:%02x:%02x" % (p["pciDomainID"], p["pciBusID"], p["pciDeviceID"])


def _worker_gpu_probe() -> dict:
    """Run a small CuPy kernel and report identity -- executed on each worker."""
    import cupy

    a = cupy.arange(1 << 16, dtype=cupy.float32)
    checksum = float((a @ a).get())  # forces real kernel launch + device sync
    dev = cupy.cuda.runtime.getDevice()
    p = cupy.cuda.runtime.getDeviceProperties(dev)
    name = p["name"]
    if isinstance(name, bytes):
        name = name.decode(errors="replace")
    return {
        "pci": _gpu_pci_address(),
        "name": name,
        "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES", "<unset>"),
        "checksum": checksum,
    }


# ---------------------------------------------------------------------------
# the abTEM workload: one independent dask chunk per frozen-phonon configuration
# ---------------------------------------------------------------------------


def build_workload(abtem, configs: int, supercell: int, sampling: float, energy: float):
    """A frozen-phonon exit-wave simulation.

    Multislice over ``configs`` frozen phonons yields a Waves object whose array
    has shape (configs, gy, gx) chunked as (1, gy, gx) -- i.e. ``configs``
    independent blocks the scheduler can place on different GPU workers.
    """
    from ase.build import bulk

    atoms = bulk("Si", "diamond", a=5.43, cubic=True) * (supercell, supercell, supercell)
    frozen_phonons = abtem.FrozenPhonons(atoms, num_configs=configs, sigmas=0.1, seed=1)
    potential = abtem.Potential(frozen_phonons, sampling=sampling)
    plane_wave = abtem.PlaneWave(energy=energy)
    return plane_wave.multislice(potential)  # lazy


def _distinct_workers_from_task_stream(task_stream_data) -> set:
    workers = set()
    for record_ in task_stream_data:
        w = record_.get("worker") if isinstance(record_, dict) else None
        if w:
            workers.add(w)
    return workers


# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------


def check_environment(args) -> dict:
    section("0. Environment")
    info: dict = {}

    print(f"host={socket.gethostname()} pid={os.getpid()}", flush=True)
    for var in (
        "SLURM_JOB_ID",
        "SLURM_JOB_PARTITION",
        "SLURM_JOB_GPUS",
        "SLURM_GPUS_ON_NODE",
        "CUDA_VISIBLE_DEVICES",
    ):
        print(f"  {var}={os.environ.get(var, '<unset>')}", flush=True)
    print(f"  python={sys.version.split()[0]}", flush=True)

    # Host memory. A SIGKILL ("Killed") during cluster bring-up is almost always
    # this being too small for N dask-cuda workers in the container -- watch the
    # cgroup/job limit, not the node total.
    try:
        import psutil

        vm = psutil.virtual_memory()
        print(
            f"  host_mem: node_total={vm.total/1e9:.0f}GB available={vm.available/1e9:.0f}GB",
            flush=True,
        )
    except Exception:  # noqa: BLE001
        pass
    try:
        from distributed.system import MEMORY_LIMIT

        info["job_mem_bytes"] = int(MEMORY_LIMIT)
        print(f"  cgroup/job mem limit: {MEMORY_LIMIT/1e9:.0f}GB", flush=True)
    except Exception:  # noqa: BLE001
        pass

    def _ver(mod):
        try:
            m = importlib.import_module(mod)
            return getattr(m, "__version__", "?"), m
        except Exception as exc:  # noqa: BLE001
            return f"<not importable: {exc}>", None

    for mod in ("numpy", "dask", "distributed", "cupy"):
        v, _ = _ver(mod)
        print(f"  {mod}={v}", flush=True)

    dask_cuda_ver, dask_cuda_mod = _ver("dask_cuda")
    print(f"  dask_cuda={dask_cuda_ver}", flush=True)
    info["has_dask_cuda"] = dask_cuda_mod is not None

    # CuPy device inventory
    try:
        import cupy

        n = cupy.cuda.runtime.getDeviceCount()
        info["cupy_device_count"] = n
        for i in range(n):
            p = cupy.cuda.runtime.getDeviceProperties(i)
            name = p["name"]
            if isinstance(name, bytes):
                name = name.decode(errors="replace")
            pci = "%04x:%02x:%02x" % (p["pciDomainID"], p["pciBusID"], p["pciDeviceID"])
            mem_gb = p["totalGlobalMem"] / 1e9
            print(f"  GPU {i}: {name}  pci={pci}  {mem_gb:.0f} GB", flush=True)
    except Exception as exc:  # noqa: BLE001
        info["cupy_device_count"] = 0
        record("environment.cupy", "FAIL", f"CuPy unavailable: {exc}")
        return info

    # abTEM + multi-GPU support detection
    try:
        import abtem

        info["abtem_version"] = getattr(abtem, "__version__", "?")
        # __file__ confirms whether PYTHONPATH shadowing picked up the branch
        # checkout rather than the container's installed abTEM.
        print(f"  abtem={info['abtem_version']}  <- {abtem.__file__}", flush=True)
    except Exception as exc:  # noqa: BLE001
        record("environment.abtem", "FAIL", f"abTEM not importable: {exc}")
        return info

    has_mgpu = False
    try:
        from abtem.core.backend import is_gpu_dask_client  # noqa: F401

        from abtem.core import config as _cfg

        # the config key ships with the multi-gpu-support branch
        _cfg.get("dask.multi-gpu")
        has_mgpu = True
    except Exception:  # noqa: BLE001
        has_mgpu = False
    info["abtem_has_multigpu"] = has_mgpu

    if has_mgpu:
        record(
            "environment.abtem_multigpu_support",
            "PASS",
            "abTEM exposes is_gpu_dask_client + dask.multi-gpu",
        )
    else:
        record(
            "environment.abtem_multigpu_support",
            "WARN",
            "this abTEM lacks multi-GPU support -- bind/install the "
            "'multi-gpu-support' branch (see README); cluster tests will not "
            "distribute abTEM work",
        )

    # dask <-> dask-cuda version compatibility hint
    if info["has_dask_cuda"]:
        try:
            import dask

            req = _dask_cuda_required_dask(dask_cuda_mod)
            note = f"dask={dask.__version__}"
            if req:
                note += f", dask_cuda expects dask {req}"
            record("environment.dask_cuda", "PASS", note)
        except Exception:  # noqa: BLE001
            record("environment.dask_cuda", "PASS", "importable")
    else:
        record(
            "environment.dask_cuda",
            "WARN" if args.no_cluster else "FAIL" if not args.allow_missing_dask_cuda else "WARN",
            "dask-cuda not importable -- required for multi-GPU distribution "
            "(see README for the install recipe); falling back to per-GPU checks",
        )

    return info


def _dask_cuda_required_dask(dask_cuda_mod) -> str:
    """Best-effort read of the dask version dask-cuda was built against."""
    try:
        from importlib.metadata import requires

        for r in requires("dask-cuda") or []:
            if r.startswith("rapids-dask-dependency") or r.startswith("dask ") or r.startswith("dask="):
                return r
    except Exception:  # noqa: BLE001
        pass
    return ""


def start_cluster(args, info):
    section("1. dask-cuda cluster bring-up")
    from dask_cuda import LocalCUDACluster
    from distributed import Client

    n_expected = args.gpus or info.get("cupy_device_count", 0)
    cluster_kwargs = {"threads_per_worker": 1}
    if args.rmm_pool:
        cluster_kwargs["rmm_pool_size"] = args.rmm_pool
    if args.gpus:
        cluster_kwargs["CUDA_VISIBLE_DEVICES"] = ",".join(str(i) for i in range(args.gpus))

    # Cap each worker's memory to a share of the cgroup/job limit so a memory-
    # constrained allocation spills/pauses instead of OOM-killing the job. Without
    # this, dask-cuda may size workers from the node total and over-commit.
    mem_per_worker = None
    if info.get("job_mem_bytes") and n_expected:
        mem_per_worker = int(0.85 * info["job_mem_bytes"] / n_expected)
        cluster_kwargs["memory_limit"] = mem_per_worker

    print(
        f"  starting LocalCUDACluster: {n_expected} workers"
        + (f", ~{mem_per_worker/1e9:.0f}GB/worker" if mem_per_worker else "")
        + " (if this SIGKILLs, the job memory is too small -- see README)",
        flush=True,
    )
    cluster = LocalCUDACluster(**cluster_kwargs)
    client = Client(cluster)
    # give workers a moment to register
    try:
        client.wait_for_workers(n_expected, timeout=args.worker_timeout)
    except Exception:  # noqa: BLE001
        pass  # asserted below with a clearer message

    n_workers = len(client.scheduler_info()["workers"])
    if n_workers == n_expected:
        record("cluster.worker_count", "PASS", f"{n_workers} workers == {n_expected} GPUs")
    else:
        record(
            "cluster.worker_count",
            "FAIL",
            f"{n_workers} workers != {n_expected} expected GPUs",
        )

    nthreads = client.nthreads()
    if nthreads and all(t == 1 for t in nthreads.values()):
        record("cluster.single_threaded", "PASS", "every worker is single-threaded")
    else:
        record("cluster.single_threaded", "FAIL", f"nthreads={nthreads}")

    if info.get("abtem_has_multigpu"):
        from abtem.core.backend import is_gpu_dask_client

        if is_gpu_dask_client(client):
            record("cluster.abtem_accepts_client", "PASS", "is_gpu_dask_client(client) is True")
        else:
            record(
                "cluster.abtem_accepts_client",
                "FAIL",
                "abTEM would NOT use this client (falls back to synchronous)",
            )

    return client, cluster, n_expected


def check_gpu_coverage(client, n_expected):
    section("2. GPU coverage (each worker == a distinct physical GPU)")
    probe = client.run(_worker_gpu_probe)  # once per worker
    pcis = {}
    for worker, res in probe.items():
        print(
            f"  {worker}  gpu={res['name']}  pci={res['pci']}  "
            f"CUDA_VISIBLE_DEVICES={res['cuda_visible_devices']}",
            flush=True,
        )
        pcis[worker] = res["pci"]

    distinct = set(pcis.values())
    if len(distinct) == n_expected == len(pcis):
        record(
            "coverage.distinct_gpus",
            "PASS",
            f"{len(distinct)} workers on {len(distinct)} distinct GPUs",
        )
    else:
        record(
            "coverage.distinct_gpus",
            "FAIL",
            f"{len(pcis)} workers map to {len(distinct)} distinct GPUs "
            f"(expected {n_expected}); workers may be sharing a device",
        )


def check_abtem_distribution(abtem, client, args, n_expected, label, autostart=False):
    """Run the workload and assert the dask task stream touched every GPU worker."""
    from distributed import get_task_stream

    configs = args.configs or max(8, 2 * n_expected)
    lazy = build_workload(abtem, configs, args.supercell, args.sampling, args.energy)

    t0 = time.perf_counter()
    with get_task_stream(client) as ts:
        result = lazy.compute(progress_bar=False)
    dt = time.perf_counter() - t0

    # correctness: finite complex exit waves of the expected shape
    import numpy as np
    from abtem.core.backend import asnumpy

    arr = asnumpy(result.array)
    ok_shape = arr.shape[0] == configs and arr.ndim == 3
    ok_finite = bool(np.all(np.isfinite(arr.real)) and np.all(np.isfinite(arr.imag)))
    if ok_shape and ok_finite:
        record(
            f"abtem.{label}.correctness",
            "PASS",
            f"exit waves {arr.shape} finite; {dt:.1f}s for {configs} configs",
        )
    else:
        record(
            f"abtem.{label}.correctness",
            "FAIL",
            f"shape={arr.shape} finite={ok_finite}",
        )

    workers = _distinct_workers_from_task_stream(ts.data)
    # histogram of tasks per worker
    hist: dict = {}
    for rec in ts.data:
        w = rec.get("worker") if isinstance(rec, dict) else None
        if w:
            hist[w] = hist.get(w, 0) + 1
    for w, c in sorted(hist.items()):
        print(f"  {w}: {c} tasks", flush=True)

    if len(workers) == n_expected:
        record(
            f"abtem.{label}.distribution",
            "PASS",
            f"abTEM ran tasks on all {n_expected} GPU workers",
        )
    elif len(workers) > 1:
        record(
            f"abtem.{label}.distribution",
            "WARN",
            f"work spread over {len(workers)}/{n_expected} workers "
            f"(raise --configs above the GPU count for full coverage)",
        )
    else:
        record(
            f"abtem.{label}.distribution",
            "FAIL",
            f"work ran on {len(workers)} worker(s) -- not distributed",
        )
    return dt


def check_autocluster(abtem, args, n_expected):
    section("4. abTEM automatic multi-GPU (config['dask.multi-gpu'])")
    from abtem.core import backend as bk
    from abtem.core.backend import is_gpu_dask_client

    with abtem.config.set({"device": "gpu", "dask.multi-gpu": True}):
        # a tiny compute triggers abTEM to build its own dask-cuda cluster
        _ = build_workload(abtem, max(2, n_expected), args.supercell, args.sampling, args.energy)
        _ = _.compute(progress_bar=False)

        client = bk._cuda_cluster_client
        if client is not None and is_gpu_dask_client(client):
            record(
                "abtem.auto.cluster_started",
                "PASS",
                "abTEM auto-started a usable dask-cuda cluster",
            )
        else:
            record(
                "abtem.auto.cluster_started",
                "FAIL",
                "abTEM did not start a usable cluster from config['dask.multi-gpu']",
            )
            return
        check_abtem_distribution(abtem, client, args, n_expected, label="auto")


def check_timing(abtem, client, cluster, args, n_expected, multi_dt):
    section("5. Timing: 1 GPU vs N GPUs")
    from dask_cuda import LocalCUDACluster
    from distributed import Client

    single_cluster = LocalCUDACluster(threads_per_worker=1, CUDA_VISIBLE_DEVICES="0")
    single_client = Client(single_cluster)
    try:
        configs = args.configs or max(8, 2 * n_expected)
        lazy = build_workload(abtem, configs, args.supercell, args.sampling, args.energy)
        t0 = time.perf_counter()
        lazy.compute(progress_bar=False)
        single_dt = time.perf_counter() - t0
        speedup = single_dt / multi_dt if multi_dt else float("nan")
        detail = f"1 GPU {single_dt:.1f}s vs {n_expected} GPU {multi_dt:.1f}s -> {speedup:.1f}x"
        # scaling is workload-dependent; treat as informational unless clearly broken
        status = "PASS" if speedup > 1.2 else "WARN"
        record("timing.speedup", status, detail)
    finally:
        single_client.close()
        single_cluster.close()


def check_per_device_fallback(abtem, args, info):
    section("Fallback: per-GPU smoke test (NOT a distribution test)")
    import cupy
    import numpy as np
    from abtem.core.backend import asnumpy

    n = info.get("cupy_device_count", 0)
    all_ok = True
    for i in range(n):
        with guard(f"fallback.gpu{i}"):
            with cupy.cuda.Device(i):
                with abtem.config.set({"device": "gpu"}):
                    lazy = build_workload(abtem, 1, args.supercell, args.sampling, args.energy)
                    # force synchronous single-device execution
                    result = lazy.compute(progress_bar=False, scheduler="synchronous")
                arr = asnumpy(result.array)
                ok = bool(np.all(np.isfinite(arr.real)))
                all_ok = all_ok and ok
                record(f"fallback.gpu{i}", "PASS" if ok else "FAIL", f"exit wave {arr.shape} finite={ok}")
    if n and all_ok:
        record("fallback.summary", "PASS", f"all {n} GPUs independently ran abTEM")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def parse_args(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--gpus", type=int, default=0, help="expected GPU count (default: all visible)")
    p.add_argument("--configs", type=int, default=0, help="frozen-phonon configs (default: max(8, 2*gpus))")
    p.add_argument("--supercell", type=int, default=4, help="Si supercell repeat per axis (default 4)")
    p.add_argument("--sampling", type=float, default=0.1, help="potential real-space sampling in Angstrom")
    p.add_argument("--energy", type=float, default=200e3, help="beam energy in eV")
    p.add_argument("--rmm-pool", default="", help="RMM pool size per worker, e.g. '20GB' (optional)")
    p.add_argument("--worker-timeout", type=float, default=120.0, help="seconds to wait for workers")
    p.add_argument("--no-cluster", action="store_true", help="skip the cluster; per-GPU smoke test only")
    p.add_argument("--skip-auto", action="store_true", help="skip the automatic-cluster (config) test")
    p.add_argument("--timing", action="store_true", help="also time 1 GPU vs N GPUs")
    p.add_argument(
        "--allow-missing-dask-cuda",
        action="store_true",
        help="treat missing dask-cuda as WARN not FAIL (fallback still runs)",
    )
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    info = check_environment(args)

    if not info.get("cupy_device_count"):
        section("Summary")
        print("No CuPy GPUs visible -- aborting.", flush=True)
        return 2

    import abtem

    use_cluster = info.get("has_dask_cuda") and not args.no_cluster

    if use_cluster:
        client = cluster = None
        try:
            client, cluster, n_expected = start_cluster(args, info)
            check_gpu_coverage(client, n_expected)

            if info.get("abtem_has_multigpu"):
                multi_dt = None
                with guard("abtem.explicit"):
                    with abtem.config.set({"device": "gpu"}):
                        multi_dt = check_abtem_distribution(
                            abtem, client, args, n_expected, label="explicit"
                        )
                if args.timing and multi_dt:
                    with guard("timing"):
                        check_timing(abtem, client, cluster, args, n_expected, multi_dt)
            else:
                record(
                    "abtem.explicit",
                    "SKIP",
                    "running abTEM has no multi-GPU support",
                )
        finally:
            if client is not None:
                client.close()
            if cluster is not None:
                cluster.close()

        # automatic path needs no pre-existing client -> run after closing the above
        if info.get("abtem_has_multigpu") and not args.skip_auto:
            with guard("abtem.auto"):
                check_autocluster(abtem, args, args.gpus or info["cupy_device_count"])
    else:
        with guard("fallback"):
            check_per_device_fallback(abtem, args, info)

    # ---- summary ----
    section("Summary")
    counts = {"PASS": 0, "WARN": 0, "FAIL": 0, "SKIP": 0}
    for name, status, detail in RESULTS:
        counts[status] += 1
    for name, status, detail in RESULTS:
        if status in ("FAIL", "WARN"):
            print(f"  {status}: {name} -- {detail}", flush=True)
    print(
        f"\n{counts['PASS']} passed, {counts['WARN']} warnings, "
        f"{counts['FAIL']} failed, {counts['SKIP']} skipped",
        flush=True,
    )
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
