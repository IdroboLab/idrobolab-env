"""What the release tests of this directory share. Not a component test: it has no row in
components.tsv and verify.py never runs it. A test imports it as `import _common`, which
needs the script's own directory on sys.path (Python's default when it runs a script, but not
under PYTHONSAFEPATH=1)."""
import importlib
import os
import sys

GPAW_SRC = "/opt/src/gpaw"


def imported_from(name, src):
    """The failed-check messages of: `name` imports and comes from the tree `src`."""
    try:
        module = importlib.import_module(name)
    except ImportError as e:
        return [f"{name} does not import: {e}"]
    if not os.path.realpath(module.__file__).startswith(src + "/"):
        return [f"{name} is imported from {module.__file__}, not from {src}"]
    return []


def gpu_count():
    try:
        import cupy
        return cupy.cuda.runtime.getDeviceCount()
    except Exception:  # no CUDA runtime or no device: nothing is visible
        return 0


def compiled_in(library):
    """Does GPAW's build report the library?"""
    import gpaw
    from gpaw import fftw
    from gpaw.utilities import compiled_with_libvdwxc, compiled_with_sl
    from gpaw.utilities.elpa import LibElpa
    return {"scalapack": compiled_with_sl, "fftw": fftw.have_fftw, "elpa": LibElpa.have_elpa,
            "libxc": lambda: bool(gpaw.get_libraries()["libxc"]),
            "libvdwxc": compiled_with_libvdwxc}[library]()


def missing_libraries(libraries):
    """The failed-check messages of: GPAW is compiled with each of `libraries`."""
    return [f"GPAW is not compiled with {library}"
            for library in libraries if not compiled_in(library)]


def mpiexec(ranks):
    """The start of an mpiexec command of the image's MPICH, run inside the container.
    -bootstrap fork: inside a Slurm allocation Hydra would otherwise look for a host srun."""
    return ["mpiexec", "-bootstrap", "fork", "-n", str(ranks)]


def finish(failed, run):
    """Exit with 1 after a FAIL line per failed preflight check, else with the status `run()`
    returns."""
    for message in failed:
        print(f"FAIL preflight: {message}")
    sys.exit(1 if failed else run())
