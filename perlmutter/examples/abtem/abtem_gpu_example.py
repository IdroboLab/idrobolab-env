# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "abtem", "ase", "numpy",
#     # CuPy 14 finds the CUDA libraries in wheels ([ctk] installs them); the toolkit is kept on
#     # CUDA 12.8, the line the idrobolab container uses.
#     "cupy-cuda12x[ctk]>=14,<15", "cuda-toolkit==12.8.*",
# ]
# ///
"""Small abTEM STEM simulation on one GPU: an annular-detector (HAADF-type) scan of Si [001].

A demonstration of the workflow, not a converged simulation: it builds a Si supercell,
runs a probe scan over one unit cell with a 70-150 mrad annular detector, prints the
abTEM and CuPy versions, the device and the wall time, and writes the image
(``haadf.npy``) and the structure (``structure.cif``) to the output directory.

    uv run --script abtem_gpu_example.py                   # 1 GPU, default size
    uv run --script abtem_gpu_example.py --cells 4 --scan 64
    uv run --script abtem_gpu_example.py --device cpu --cells 1 --scan 4 --out /tmp/test

The job templates ``abtem_uv_gpu_shared.sbatch`` and ``abtem_uv_gpu_node.sbatch`` run it
with the environment ``~/venvs/abtem`` (perlmutter/docs/07-abtem.md). One process uses
one GPU; spreading a single calculation over several GPUs needs dask-cuda and runs
in the idrobolab container.

The wall time covers the whole scan, including first-call costs (FFT plans, kernel
compilation), so it overstates the cost per probe position for small ``--scan``.
"""
import argparse
import os
import time
from pathlib import Path

import abtem
import cupy
import numpy as np
from ase.build import bulk
from ase.io import write


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", choices=["gpu", "cpu"], default="gpu")
    parser.add_argument("--cells", type=int, default=2,
                        help="lateral repeats of the 5.43 A cubic cell (default 2)")
    parser.add_argument("--energy", type=float, default=200,
                        help="electron energy in keV (default 200)")
    parser.add_argument("--scan", type=int, default=16,
                        help="probe positions per side of the scanned unit cell (default 16)")
    parser.add_argument("--out", type=Path,
                        default=Path(os.environ.get("SCRATCH", ".")) / "abtem-example",
                        help="output directory (default $SCRATCH/abtem-example)")
    args = parser.parse_args()

    print("abtem", abtem.__version__, "| cupy", cupy.__version__)
    if args.device == "gpu":
        runtime = cupy.cuda.runtime
        properties = runtime.getDeviceProperties(0)
        print("CUDA runtime", runtime.runtimeGetVersion(), "| driver", runtime.driverGetVersion(),
              "|", properties["name"].decode(), "| PCI bus", properties["pciBusID"])
    abtem.config.set({"device": args.device})

    cell = bulk("Si", cubic=True)
    atoms = cell.repeat((args.cells, args.cells, 4))
    potential = abtem.Potential(atoms, sampling=0.05, slice_thickness=2.0)
    probe = abtem.Probe(energy=args.energy * 1e3, semiangle_cutoff=20)
    detector = abtem.AnnularDetector(inner=70, outer=150)
    a = cell.cell[0, 0]
    scan = abtem.GridScan(start=(0, 0), end=(a, a), gpts=args.scan, endpoint=False)
    print(f"device {args.device} | {args.energy:g} keV | {len(atoms)} atoms | potential grid {potential.gpts} "
          f"| {args.scan}x{args.scan} probe positions")

    start = time.perf_counter()
    image = probe.scan(potential, scan=scan, detectors=detector).compute(progress_bar=False)
    array = image.to_cpu().array
    print(f"scan time {time.perf_counter() - start:.2f} s")
    print(f"image {array.shape}: min {array.min():.4g}, max {array.max():.4g}, mean {array.mean():.4g}")

    args.out.mkdir(parents=True, exist_ok=True)
    np.save(args.out / "haadf.npy", array)
    write(args.out / "structure.cif", atoms)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
