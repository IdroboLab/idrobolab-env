#!/bin/bash
# Full quad-A100 GPU node (exclusive): one Python process driving all 4 GPUs.
# For abTEM multi-GPU dask scheduling, torch/jax multi-device work, or any
# job that needs the whole node's 256 GB host RAM.
#
# Node: 1x AMD EPYC 7763 (Milan), 64 physical cores (128 logical), 256 GB DDR4,
#       4x A100 40 GB HBM2 (NVLink3, 4 links per GPU pair), 4x Slingshot-11.
# Charging: walltime x 1 node x 1.0 — i.e. 4x what the shared 1-GPU script
# costs per hour. Use gpu_1gpu_shared.sbatch unless you really need 4 GPUs.
#
# Usage:  sbatch gpu_4gpu_node.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_4gpu
#SBATCH --account=<project>_g          # <- replace; GPU account = _g suffix
#SBATCH --constraint=gpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1            # single process, 4 visible GPUs
#SBATCH --cpus-per-task=128            # all logical CPUs on the node
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=none                # all 4 GPUs visible to the one task
#SBATCH --exclusive
#SBATCH --time=02:00:00
#SBATCH --output=%x_%j.out

set -euo pipefail

IMAGE=${IMAGE:-ghcr.io/<username>/otherimage:latest}
SCRIPT=${1:?usage: sbatch gpu_4gpu_node.sbatch script.py [args]}
shift

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

# Run a cluster checkout instead of the baked-in code:
# MOUNTS="$MOUNTS -v $SCRATCH/code/abTEM:/opt/src/abTEM"

# One process, 4 GPUs: leave room for the CUDA/dask worker threads rather
# than pinning everything to one thread.
THREAD_ENV="-e OMP_NUM_THREADS=16 -e OPENBLAS_NUM_THREADS=16"

echo "IMAGE=$IMAGE  gpus=4  mounts=$MOUNTS"
time srun --cpu-bind=none \
    podman-hpc run --rm --gpu \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        $THREAD_ENV \
        "$IMAGE" python "$SCRIPT" "$@"

# For 4 MPI ranks x 1 GPU each on this node instead of one 4-GPU process, use
# gpu_multinode_mpi.sbatch with --nodes=1 — it has the rank/GPU binding set up.
