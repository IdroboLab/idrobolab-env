#!/bin/bash
# install-jupyter-kernel.sh — register a Jupyter kernel so jupyter.nersc.gov
# runs YOUR environment: a container image, a uv/virtualenv venv, or a conda
# env. Run it once on a Perlmutter login node; the kernel then appears in the
# JupyterHub launcher with no tunnel and no terminal to keep open.
#
# Usage:
#   ./install-jupyter-kernel.sh --venv  /global/common/software/<project>/venvs/analysis \
#                               --name analysis --display "Analysis (venv)"
#   ./install-jupyter-kernel.sh --conda ~/.conda/envs/myenv --name myenv
#   ./install-jupyter-kernel.sh --image ghcr.io/<username>/idrobolab:latest \
#                               --name idrobolab --display "idrobolab (GPU)" --gpu
#
#   ./install-jupyter-kernel.sh --list
#   ./install-jupyter-kernel.sh --remove idrobolab
#
# Options:
#   --venv DIR | --conda DIR | --image REF   what the kernel runs (pick one)
#   --name ID          kernel id (directory name). Default: derived from the target
#   --display "TEXT"   name shown in the launcher. Default: the id
#   --gpu              container only: pass --gpu to podman-hpc
#   --mount PATH       container only: extra bind mount, repeatable
#   --env K=V          extra environment variable for the kernel, repeatable
#   --prefix DIR       install under DIR/kernels/ instead of ~/.local/share/jupyter
#   --force            overwrite an existing kernel of the same name
#   --dry-run          print the kernel.json instead of writing it
#
# This is a LOGIN-NODE setup script; the kernel itself runs wherever
# JupyterHub puts it. For a session on a node you allocate yourself, with an
# ssh tunnel and the exact image the batch jobs use, see
# ../jobs/interactive_jupyter.sh instead. Both routes: ../jupyter.md
set -euo pipefail

BACKEND="" TARGET="" NAME="" DISPLAY="" PREFIX="" GPU=0 FORCE=0 DRY=0
EXTRA_MOUNTS=() EXTRA_ENV=()

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --venv)    BACKEND=venv;  TARGET=${2:?--venv needs a path};  shift 2 ;;
        --conda)   BACKEND=conda; TARGET=${2:?--conda needs a path}; shift 2 ;;
        --image)   BACKEND=image; TARGET=${2:?--image needs a reference}; shift 2 ;;
        --name)    NAME=${2:?};    shift 2 ;;
        --display) DISPLAY=${2:?}; shift 2 ;;
        --prefix)  PREFIX=${2:?};  shift 2 ;;
        --mount)   EXTRA_MOUNTS+=("${2:?}"); shift 2 ;;
        --env)     EXTRA_ENV+=("${2:?}");    shift 2 ;;
        --gpu)     GPU=1;   shift ;;
        --force)   FORCE=1; shift ;;
        --dry-run) DRY=1;   shift ;;
        --list)    LIST=1;  shift ;;
        --remove)  REMOVE=${2:?--remove needs a kernel name}; shift 2 ;;
        -h|--help) usage 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

KERNEL_ROOT="${PREFIX:-$HOME/.local/share/jupyter}/kernels"

if [ -n "${LIST:-}" ]; then
    echo "kernels in $KERNEL_ROOT:"
    [ -d "$KERNEL_ROOT" ] || { echo "  (none — directory does not exist)"; exit 0; }
    _found=0
    for d in "$KERNEL_ROOT"/*/; do
        [ -f "$d/kernel.json" ] || continue
        _found=1
        printf '  %-24s %s\n' "$(basename "$d")" \
            "$(sed -n 's/.*"display_name": *"\([^"]*\)".*/\1/p' "$d/kernel.json")"
    done
    [ "$_found" = 1 ] || echo "  (none)"
    exit 0
fi

if [ -n "${REMOVE:-}" ]; then
    d="$KERNEL_ROOT/$REMOVE"
    [ -d "$d" ] || die "no such kernel: $d"
    [ -f "$d/kernel.json" ] || die "$d has no kernel.json — refusing to delete it"
    rm -rf "$d"
    echo ">> removed $d"
    exit 0
fi

[ -n "$BACKEND" ] || usage 1

# --- resolve the interpreter / image -----------------------------------------
# For venv and conda the kernel runs a python DIRECTLY, by absolute path. That
# is deliberate: `conda run` captures output by default and has a long history
# of breaking interactive kernels, and `conda activate` needs a shell whose
# rc files JupyterHub does not source. The bin/python of an env already has
# the right sys.prefix baked in, which is all a kernel needs.
case "$BACKEND" in
    venv|conda)
        TARGET=$(cd "$TARGET" 2>/dev/null && pwd -P) \
            || die "not a directory: $TARGET"
        PY="$TARGET/bin/python"
        [ -x "$PY" ] || die "no interpreter at $PY"
        # ipykernel is what the hub actually launches; a kernel without it
        # installs cleanly and then dies at first use with a traceback that
        # does not mention the real problem.
        "$PY" -c 'import ipykernel' 2>/dev/null \
            || die "$PY cannot import ipykernel — install it into that env first
       (uv pip install --python "$PY" ipykernel, or conda install ipykernel)"
        DEFAULT_NAME=$(basename "$TARGET")
        ;;
    image)
        case "$TARGET" in
            */*) : ;;
            *)   TARGET="ghcr.io/${IMAGE_OWNER:-<username>}/${TARGET}:${TAG:-latest}" ;;
        esac
        DEFAULT_NAME=$(basename "${TARGET%%:*}")
        command -v podman-hpc >/dev/null 2>&1 \
            || echo "WARNING: podman-hpc not on PATH here; the kernel will still" \
                    "need it wherever JupyterHub runs it." >&2
        ;;
esac

NAME=${NAME:-$DEFAULT_NAME}
DISPLAY=${DISPLAY:-$NAME}
case "$NAME" in
    *[!A-Za-z0-9._-]*) die "kernel name has characters Jupyter will not accept: $NAME" ;;
esac

# --- container mounts ---------------------------------------------------------
# The hub writes the connection file under $HOME and passes its path as
# {connection_file}; the container must see that exact path or the kernel
# cannot be reached. $HOME is therefore not optional here.
#
# Same cdirs/projectdirs twin as the job templates -- see ../jobs/README.md.
MOUNTS=""
_mounted=""
add_mount() {
    local p=${1:-} m twin
    [ -n "$p" ] && [ -d "$p" ] || return 0
    p=$(cd "$p" && pwd -P)
    for m in $_mounted; do
        case "$p" in "$m" | "$m"/*) return 0 ;; esac
    done
    _mounted="$_mounted $p"
    MOUNTS="$MOUNTS -v $p:$p"
    case "$p" in
        /global/cfs/cdirs/*)
            twin="/global/cfs/projectdirs/${p#/global/cfs/cdirs/}"
            if [ -d "$twin" ]; then MOUNTS="$MOUNTS -v $twin:$twin"
            else                    MOUNTS="$MOUNTS -v $p:$twin"; fi ;;
    esac
}

# --- build argv ---------------------------------------------------------------
ARGV=()
case "$BACKEND" in
    venv|conda)
        ARGV=("$PY" -m ipykernel_launcher -f '{connection_file}')
        ;;
    image)
        for p in "$HOME" "${SCRATCH:-}" "${CFS:-}" "${EXTRA_MOUNTS[@]:-}"; do
            add_mount "$p"
        done
        # --network host is REQUIRED and is the whole reason a container kernel
        # is more than a wrapper. A kernel is not a server you connect to: the
        # hub connects INTO it, on five ZMQ ports named in {connection_file}.
        # podman-hpc containers get a PRIVATE network namespace (see
        # ../podman-hpc.md, "Networking"), so those ports are unreachable from
        # the hub -- and -p cannot help, because the ports are chosen per
        # launch. Host networking is the only way the hub can reach the kernel.
        ARGV=(podman-hpc run --rm -i --network host --group-add keep-groups)
        [ "$GPU" = 1 ] && ARGV+=(--gpu)
        # shellcheck disable=SC2206
        ARGV+=($MOUNTS)
        ARGV+=(-e "HOME=$HOME" "$TARGET"
               python -m ipykernel_launcher -f '{connection_file}')
        ;;
esac

# --- emit kernel.json ---------------------------------------------------------
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

kernel_json() {
    printf '{\n  "argv": [\n'
    local first=1 a
    for a in "${ARGV[@]}"; do
        [ "$first" = 1 ] || printf ',\n'
        first=0
        printf '    "%s"' "$(json_escape "$a")"
    done
    printf '\n  ],\n'
    printf '  "display_name": "%s",\n' "$(json_escape "$DISPLAY")"
    printf '  "language": "python"'
    if [ "${#EXTRA_ENV[@]}" -gt 0 ]; then
        printf ',\n  "env": {\n'
        first=1
        for a in "${EXTRA_ENV[@]}"; do
            case "$a" in *=*) : ;; *) die "--env needs K=V, got: $a" ;; esac
            [ "$first" = 1 ] || printf ',\n'
            first=0
            printf '    "%s": "%s"' \
                "$(json_escape "${a%%=*}")" "$(json_escape "${a#*=}")"
        done
        printf '\n  }'
    fi
    printf '\n}\n'
}

if [ "$DRY" = 1 ]; then
    kernel_json
    exit 0
fi

DEST="$KERNEL_ROOT/$NAME"
if [ -e "$DEST" ] && [ "$FORCE" != 1 ]; then
    die "$DEST already exists (use --force to overwrite, or --remove $NAME first)"
fi
mkdir -p "$DEST"
kernel_json > "$DEST/kernel.json"

echo ">> installed kernel '$NAME' ($BACKEND) at $DEST/kernel.json"
echo "   display name: $DISPLAY"
if [ -n "$PREFIX" ]; then
    echo "   NOTE: a non-default --prefix is only found if JUPYTER_PATH includes"
    echo "         ${PREFIX%/}, which JupyterHub does not set for you."
fi
if [ "$BACKEND" = image ]; then
    echo
    echo "   NOTE: the container kernel relies on --network host so the hub can"
    echo "   reach the kernel ZMQ ports. That flag is REQUIRED (podman-hpc gives"
    echo "   containers a private namespace) but has not been verified against"
    echo "   podman-hpc itself. If the kernel dies at startup, check that first:"
    echo "     podman-hpc run --rm --network host $TARGET true"
fi
echo
echo "   Next: open https://jupyter.nersc.gov, start a Perlmutter server, and"
echo "   pick '$DISPLAY' in the launcher. If it is missing, the hub caches the"
echo "   kernel list -- restart the Jupyter server from the Hub Control Panel."
