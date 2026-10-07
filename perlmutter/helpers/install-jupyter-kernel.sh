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
#   --shared           install project-wide under /global/common/software/<project>
#                      /share/jupyter, group-readable, for everyone in the project
#   --link [DIR]       (each user, once) symlink every kernel from the shared
#                      dir into ~/.local/share/jupyter/kernels, so Jupyter finds
#                      them with no environment variable at all
#   --force            overwrite an existing kernel of the same name
#   --dry-run          print the kernel.json instead of writing it
#
# This is a LOGIN-NODE setup script; the kernel itself runs wherever
# JupyterHub puts it. For a session on a node you allocate yourself, with an
# ssh tunnel and the exact image the batch jobs use, see
# ../jobs/interactive_jupyter.sh instead. Both routes: docs/perlmutter/reference/jupyter.md
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
        --shared)  SHARED=1;       shift ;;
        --link)    case "${2:-}" in -*|"") LINK=default; shift ;;
                                    *)     LINK=$2; shift 2 ;; esac ;;
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

# --shared writes to the project's /global/common tree: read-optimized, visible
# from every node, and the same place install-uv.sh puts shared interpreters.
# Jupyter does not search there by default; each user runs --link once.
if [ -n "${SHARED:-}" ]; then
    [ -n "$PREFIX" ] && die "--shared and --prefix are mutually exclusive"
    PREFIX="/global/common/software/${NERSC_PROJECT:-<project>}/share/jupyter"
fi
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

# Jupyter always searches ~/.local/share/jupyter/kernels, so a symlink there is
# found with nothing else to configure. The kernel.json stays in the project
# tree, so the maintainer updates it for everyone in one place.
if [ -n "${LINK:-}" ]; then
    [ "$LINK" = default ] && LINK="/global/common/software/${NERSC_PROJECT:-<project>}/share/jupyter"
    src="${LINK%/}/kernels"
    [ -d "$src" ] || die "no kernels directory at $src"
    dest="$HOME/.local/share/jupyter/kernels"
    mkdir -p "$dest"
    # Clear symlinks that no longer resolve: they are the residue of a shared
    # kernel that has been removed or renamed, and Jupyter reports them as
    # broken kernels rather than ignoring them.
    for l in "$dest"/*; do
        if [ -L "$l" ] && [ ! -e "$l" ]; then
            rm -f "$l"; echo "  pruned $(basename "$l") (shared kernel is gone)"
        fi
    done
    n=0
    for d in "$src"/*/; do
        [ -f "$d/kernel.json" ] || continue
        name=$(basename "$d")
        if [ -e "$dest/$name" ] && [ ! -L "$dest/$name" ]; then
            echo "SKIP $name -- a real directory of that name already exists in $dest" >&2
            continue
        fi
        ln -sfn "${d%/}" "$dest/$name"
        echo "  linked $name"
        n=$((n + 1))
    done
    echo ">> $n kernel(s) linked from $src into $dest"
    echo "   Restart your Jupyter server from the Hub Control Panel to see them."
    exit 0
fi

if [ -n "${REMOVE:-}" ]; then
    d="$KERNEL_ROOT/$REMOVE"
    # A symlink is one of ours pointing at a shared kernel -- drop the link and
    # never follow it, or removing your own copy would delete the project's.
    # Handle a BROKEN one too: that is exactly what a user is left holding after
    # the shared kernel it pointed at is removed.
    if [ -L "$d" ]; then
        rm -f "$d"
        echo ">> removed symlink $d (the shared kernel it pointed at is untouched)"
        exit 0
    fi
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
        # Bake in the absolute path. JupyterHub launches the kernel from its own
        # environment, not from a login shell, so a bare `podman-hpc` in argv is
        # a bet on the hub PATH -- and when it loses, the kernel dies at startup
        # with a message about the kernel, not about PATH.
        PODMAN_BIN=$(command -v podman-hpc 2>/dev/null || true)
        if [ -z "$PODMAN_BIN" ]; then
            PODMAN_BIN=podman-hpc
            echo "WARNING: podman-hpc is not on PATH here, so the kernel will call" >&2
            echo "         it by bare name and depend on the hub PATH. Run this on a" >&2
            echo "         Perlmutter login node to bake in the absolute path." >&2
        fi
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
    local p=${1:-} m twin given
    [ -n "$p" ] && [ -d "$p" ] || return 0
    given=$p
    p=$(cd "$p" && pwd -P)
    for m in $_mounted; do
        case "$p" in "$m" | "$m"/*) return 0 ;; esac
    done
    _mounted="$_mounted $p"
    MOUNTS="$MOUNTS -v $p:$p"
    # Also mount it under the name we were GIVEN, when that is a symlink to the
    # canonical one. $HOME is the case that matters: NERSC sets it to
    # /global/homes/<i>/<user>, a symlink to /global/u1/<i>/<user>. Mounting only
    # the resolved name leaves $HOME itself non-existent inside the container --
    # which reads as "not a writable location", and anything that resolves $HOME
    # (Jupyter runtime dirs, ~/.config) lands in the ephemeral overlay instead.
    [ "$given" = "$p" ] || MOUNTS="$MOUNTS -v $p:$given"
    # $CFS is often the bare /global/cfs/cdirs, so match that too -- the
    # /*-only pattern silently produced no twin at all for it.
    case "$p" in
        /global/cfs/cdirs)   twin="/global/cfs/projectdirs" ;;
        /global/cfs/cdirs/*) twin="/global/cfs/projectdirs/${p#/global/cfs/cdirs/}" ;;
        *)                   twin="" ;;
    esac
    if [ -n "$twin" ] && [ "$twin" != "$given" ]; then
        if [ -d "$twin" ]; then
            MOUNTS="$MOUNTS -v $twin:$twin"
        else
            MOUNTS="$MOUNTS -v $p:$twin"
        fi
    fi
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
        # --network host is required: the hub connects INTO the kernel, on five
        # ZMQ ports named in {connection_file} and chosen per launch, so -p
        # cannot publish them. See docs/perlmutter/reference/podman-hpc.md, "Networking".
        # The connection file's directory has to be mounted, and we cannot know
        # it at install time: a bare KernelManager drops it in tempfile.gettempdir()
        # (/tmp, private to the container), jupyter_server puts it in the runtime
        # dir, and JUPYTER_RUNTIME_DIR can move it anywhere. Getting it wrong is
        # silent -- ipykernel cannot write where it was told, generates its own
        # ports, and the client waits forever on the ports it chose.
        #
        # So resolve it at LAUNCH time: a one-line bash wrapper takes the
        # substituted path as $1 and mounts its directory, unless one of the
        # static mounts already covers it (an identical -v destination is a hard
        # podman error, whereas a nested one is harmless).
        # JupyterHub launches a kernel without a login shell, so ~/.bashrc --
        # and therefore env.sh -- never runs. Without this the kernel starts,
        # podman-hpc cannot see the shared CFS store, and it fails with
        # "image not known" for an image that `podman-hpc images` lists happily
        # on a login node. Capture it at install time, when env.sh HAS run.
        # An explicit --env of the same name wins.
        case " ${EXTRA_ENV[*]:-} " in
            *" PODMANHPC_ADDITIONAL_STORES="*) : ;;
            *)  if [ -n "${PODMANHPC_ADDITIONAL_STORES:-}" ]; then
                    EXTRA_ENV+=("PODMANHPC_ADDITIONAL_STORES=$PODMANHPC_ADDITIONAL_STORES")
                else
                    echo "WARNING: PODMANHPC_ADDITIONAL_STORES is not set here, so the" >&2
                    echo "         kernel will not know about the shared image store." >&2
                    echo "         Run \`. ../env.sh\` first, then re-run with --force." >&2
                fi ;;
        esac

        _gpu=""; [ "$GPU" = 1 ] && _gpu="--gpu"
        _covered=""
        for m in $_mounted; do _covered="$_covered$m|$m/*|"; done
        WRAPPER="d=\$(dirname \"\$1\"); extra=; case \"\$d\" in ${_covered%|}) ;; *) extra=\"-v \$d:\$d\" ;; esac; exec $PODMAN_BIN run --rm -i --network host --group-add keep-groups $_gpu \$extra $MOUNTS -e HOME=$HOME $TARGET python -m ipykernel_launcher -f \"\$1\""
        ARGV=(/bin/bash -c "$WRAPPER" kernel '{connection_file}')
        ;;
esac

# --- emit kernel.json ---------------------------------------------------------
# JSON string escaping: backslash, quote, and the control characters a shell
# snippet can plausibly contain (a raw newline in a JSON string is invalid).
json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
        | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

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

# A shared kernel is useless if the group cannot read it, and the default umask
# on a personal file leaves it 0600. Same problem install-uv.sh exists to solve.
if [ -n "${SHARED:-}" ]; then
    chgrp -R "${NERSC_PROJECT:-<project>}" "$DEST" 2>/dev/null \
        || echo "WARNING: could not chgrp $DEST to ${NERSC_PROJECT:-<project>}" >&2
    chmod -R g+rX "$DEST" 2>/dev/null \
        || echo "WARNING: could not make $DEST group-readable" >&2
fi

echo ">> installed kernel '$NAME' ($BACKEND) at $DEST/kernel.json"
echo "   display name: $DISPLAY"
if [ -n "$PREFIX" ]; then
    echo
    echo "   Jupyter does not search ${PREFIX%/}. Each user runs this once,"
    echo "   and then sees every kernel installed there, now and later:"
    echo
    echo "     $0 --link ${PREFIX%/}"
fi
echo
echo "   Next: open https://jupyter.nersc.gov, start a Perlmutter server, and"
echo "   pick '$DISPLAY' in the launcher. If it is missing, the hub caches the"
echo "   kernel list -- restart the Jupyter server from the Hub Control Panel."
