#!/bin/bash
# setup-user.sh — one-shot per-user setup for this project on Perlmutter.
# Idempotent: re-run it after the repo changes, or any time you are unsure.
#
# Published into the shared bin dir, so for most people it is simply:
#
#     hpcenvs-setup            # do it
#     hpcenvs-setup --check    # report only, change nothing
#     hpcenvs-setup --undo     # remove the block it added from your startup file
#
# What it does:
#   1. sources env.sh from your shell startup file (image store, aliases, PATH)
#   2. links the project's shared Jupyter kernels into your own kernel dir
#   3. checks the things that silently break later: project group membership,
#      whether the shared image store is actually readable by you, $SCRATCH
#
# Maintainer, once:  ./setup-user.sh --publish
#   symlinks it into /global/common/software/<project>/bin as `hpcenvs-setup`.
set -euo pipefail

CHECK=0 PUBLISH=0 UNDO=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   CHECK=1;   shift ;;
        --publish) PUBLISH=1; shift ;;
        --undo)    UNDO=1;    shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
done

# Resolve through the published symlink, or --publish and the helper calls
# below would resolve relative to the bin dir instead of the checkout.
SELF=$(readlink -f "${BASH_SOURCE[0]}")
HELPERS=$(dirname "$SELF")
PERLMUTTER=$(dirname "$HELPERS")
PROJECT="${NERSC_PROJECT:-<project>}"
SHARED_JUPYTER="${HPCENVS_SHARED_JUPYTER:-/global/common/software/${PROJECT}/share/jupyter}"
BIN_DIR="/global/common/software/${PROJECT}/bin"

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
act()  { printf '  \033[36mdid\033[0m   %s\n' "$*"; }
WARNINGS=0

# --- maintainer: publish into the shared bin ---------------------------------
if [ "$PUBLISH" = 1 ]; then
    [ -d "$BIN_DIR" ] || { echo "ERROR: $BIN_DIR does not exist" >&2; exit 1; }
    ln -sfn "$SELF" "$BIN_DIR/hpcenvs-setup"
    chgrp "$PROJECT" "$BIN_DIR/hpcenvs-setup" 2>/dev/null || true
    chmod g+rX "$BIN_DIR/hpcenvs-setup" 2>/dev/null || true
    echo ">> published $BIN_DIR/hpcenvs-setup -> $SELF"
    echo "   Group members with env.sh sourced have that on PATH already."
    exit 0
fi

# --- undo: remove our block, leave everything else alone ---------------------
# Only the marked block, never the whole file: people put their own things in
# these files, and a startup file is not ours to reset.
if [ "$UNDO" = 1 ]; then
    removed=0
    for rc in "$HOME/.bashrc.ext" "$HOME/.bashrc"; do
        [ -f "$rc" ] || continue
        grep -qF "# >>> hpcenvs (${PROJECT}) >>>" "$rc" || continue
        cp -p "$rc" "$rc.hpcenvs-backup"
        sed -i "/^# >>> hpcenvs (${PROJECT}) >>>$/,/^# <<< hpcenvs (${PROJECT}) <<<$/d" "$rc"
        # ...including the blank line we wrote before it, so the file comes back
        # byte-identical when ours was the only addition.
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$rc"
        echo ">> removed the hpcenvs block from $rc (backup: $rc.hpcenvs-backup)"
        removed=1
    done
    if [ "$removed" = 0 ]; then
        echo ">> no hpcenvs block found in ~/.bashrc.ext or ~/.bashrc"
    else
        echo "   Open a new shell; the current one still has env.sh applied."
    fi
    exit 0
fi

echo "hpcenvs user setup — project $PROJECT"
[ "$CHECK" = 1 ] && echo "(--check: reporting only, nothing will be changed)"
echo

# --- 1. shell startup --------------------------------------------------------
# NERSC's own ~/.bashrc is managed and carries a "do not edit" banner; the
# supported place for user customisation is ~/.bashrc.ext, which it sources.
# Prefer that where it exists so an upstream refresh of ~/.bashrc cannot
# silently drop our line.
echo "1. shell startup"
if [ -f "$HOME/.bashrc.ext" ]; then
    RC="$HOME/.bashrc.ext"
else
    RC="$HOME/.bashrc"
fi
MARK="# >>> hpcenvs (${PROJECT}) >>>"
ENDMARK="# <<< hpcenvs (${PROJECT}) <<<"
LINE=". ${PERLMUTTER}/env.sh"

if [ -f "$RC" ] && grep -qF "$MARK" "$RC"; then
    if grep -qF "$LINE" "$RC"; then
        ok "$RC already sources env.sh"
    else
        warn "$RC has an hpcenvs block, but pointing somewhere else --"
        warn "  edit it by hand, or delete the block and re-run"
    fi
elif [ "$CHECK" = 1 ]; then
    warn "$RC does not source env.sh (run without --check to add it)"
else
    {
        echo ""
        echo "$MARK"
        echo "# Added by setup-user.sh. Safe to source anywhere: it is silent,"
        echo "# idempotent, and does nothing off Perlmutter."
        echo "[ -r \"${PERLMUTTER}/env.sh\" ] && $LINE"
        echo "$ENDMARK"
    } >> "$RC"
    act "added env.sh to $RC"
    act "run '. $RC' or open a new shell to pick it up now"
fi
echo

# --- 2. shared Jupyter kernels ----------------------------------------------
echo "2. Jupyter kernels"
if [ -d "$SHARED_JUPYTER/kernels" ]; then
    if [ "$CHECK" = 1 ]; then
        n=$(find "$SHARED_JUPYTER/kernels" -mindepth 2 -maxdepth 2 -name kernel.json 2>/dev/null | wc -l)
        linked=$(find "$HOME/.local/share/jupyter/kernels" -maxdepth 1 -type l 2>/dev/null | wc -l)
        ok "$n shared kernel(s) available, $linked linked into your kernel dir"
    else
        "$HELPERS/install-jupyter-kernel.sh" --link "$SHARED_JUPYTER" | sed 's/^/  /'
    fi
else
    ok "no shared kernels published yet — nothing to link"
fi
echo

# --- 3. the things that break later -----------------------------------------
echo "3. checks"

# Project group. Container access to /global/cfs/cdirs/<project> comes from a
# SUPPLEMENTARY group; without it, jobs fail with a "Permission denied" on a
# path your login shell can read, which looks like anything but a group problem.
if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx "$PROJECT"; then
    ok "you are in the $PROJECT group"
else
    warn "you are NOT in the $PROJECT group — container jobs will fail with"
    warn "  'Permission denied' on /global/cfs/cdirs/$PROJECT. Ask the PI to add you."
fi

# The shared image store. This is the check worth having: the store lives on
# CFS and has to stay group-readable, and when it is not, the failure surfaces
# much later inside a job as "manifest ... file does not exist".
if command -v podman-hpc >/dev/null 2>&1; then
    if [ -n "${PODMANHPC_ADDITIONAL_STORES:-}" ]; then
        if podman-hpc images 2>/dev/null | grep -qE 'idrobolab|otherimage'; then
            ok "shared image store is readable ($PODMANHPC_ADDITIONAL_STORES)"
        else
            warn "no project images visible in $PODMANHPC_ADDITIONAL_STORES"
            warn "  a maintainer may need: $HELPERS/fix-store-perms.sh --check"
        fi
    else
        warn "PODMANHPC_ADDITIONAL_STORES unset — open a new shell after step 1"
    fi
else
    warn "podman-hpc not on PATH (are you on a login node?)"
fi

# Scratch. Purged after 8 weeks without access, which is why campaign results
# belong on CFS -- worth knowing before you put six months of work there.
if [ -n "${SCRATCH:-}" ] && [ -d "$SCRATCH" ]; then
    ok "\$SCRATCH is $SCRATCH (purged after 8 weeks without access)"
else
    warn "\$SCRATCH is not set or missing"
fi

# $HOME is small and, on NERSC, quota'd well below what a container workflow
# will produce. Point people at the right filesystem before they fill it.
ok "keep data on \$SCRATCH or \$CFS, not \$HOME (run 'myquota' to see why)"

echo
if [ "$WARNINGS" -eq 0 ]; then
    echo "All good."
else
    echo "$WARNINGS warning(s) above."
fi
echo
echo "Next steps, none of them automatic:"
echo "  * notebooks:        $PERLMUTTER/jupyter.md"
echo "  * batch templates:  $PERLMUTTER/jobs/README.md"
echo "  * container notes:  $PERLMUTTER/podman-hpc.md"
echo "  * from a laptop, set up sshproxy so ssh does not prompt every time:"
echo "    https://docs.nersc.gov/connect/mfa/#sshproxy"
