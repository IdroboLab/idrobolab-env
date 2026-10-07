#!/bin/bash
# setup-user.sh — one-shot per-user setup for this project on Perlmutter.
# Idempotent: re-run it after the repo changes, or any time you are unsure.
#
# Run it from your own clone of idrobolab-env:
#
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh           # do it
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh --check   # report only, change nothing
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh --undo    # remove the block it added
#
# The block sources env.sh from the clone the script runs from. A block written
# from another checkout is reported, not replaced: --undo, then run it again.
#
# What it does:
#   1. sources env.sh from your shell startup file (image store, aliases, PATH)
#   2. links the project's shared Jupyter kernels into your own kernel dir
#   3. checks the things that silently break later: project group membership,
#      whether the shared image store is actually readable by you, $SCRATCH
#   4. if you ran setup-agents.sh, shows its --check result
set -euo pipefail

CHECK=0 UNDO=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   CHECK=1;   shift ;;
        --undo)    UNDO=1;    shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
done

# The clone's path as the user reaches it (/global/homes/..., not the physical
# home path), so the block keeps working if NERSC moves the home directory.
HELPERS=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PERLMUTTER=$(dirname "$HELPERS")
PROJECT="${NERSC_PROJECT:-<project>}"
SHARED_JUPYTER="${HPCENVS_SHARED_JUPYTER:-/global/common/software/${PROJECT}/share/jupyter}"

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
act()  { printf '  \033[36mdid\033[0m   %s\n' "$*"; }
WARNINGS=0

# --- undo: remove our block, leave everything else alone ---------------------
# Only the marked block, never the whole file: people put their own things in
# these files, and a startup file is not ours to reset.
if [ "$UNDO" = 1 ]; then
    removed=0
    for rc in "$HOME/.bashrc.ext" "$HOME/.bashrc"; do
        [ -f "$rc" ] || continue
        grep -qF "# >>> hpcenvs (${PROJECT}) >>>" "$rc" || continue
        cp -p "$rc" "$rc.hpcenvs-backup"
        sed -i --follow-symlinks "/^# >>> hpcenvs (${PROJECT}) >>>$/,/^# <<< hpcenvs (${PROJECT}) <<<$/d" "$rc"
        # ...including the blank line we wrote before it, so the file comes back
        # byte-identical when ours was the only addition.
        sed -i --follow-symlinks -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$rc"
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

echo "idrobolab-env user setup — project $PROJECT"
[ "$CHECK" = 1 ] && echo "(--check: reporting only, nothing will be changed)"
echo

# --- 1. shell startup --------------------------------------------------------
# ~/.bashrc, per NERSC's current guidance: the .bashrc.ext / .bash_profile.ext
# split is deprecated and the standard dotfiles are yours to edit.
# https://docs.nersc.gov/environment/#customizing-your-shell-environment
echo "1. shell startup"
RC="$HOME/.bashrc"
MARK="# >>> hpcenvs (${PROJECT}) >>>"
ENDMARK="# <<< hpcenvs (${PROJECT}) <<<"
ENVSH="${PERLMUTTER}/env.sh"

# An account created before February 2020 may still have a .ext file, and an
# earlier version of this script wrote the block there. Find it wherever it is,
# so a re-run neither duplicates the block nor reports it missing.
FOUND_IN=""
for rc in "$RC" "$HOME/.bashrc.ext"; do
    [ -f "$rc" ] && grep -qF "$MARK" "$rc" && { FOUND_IN=$rc; break; }
done

if [ -n "$FOUND_IN" ]; then
    if grep -qF "$ENVSH" "$FOUND_IN"; then
        ok "$FOUND_IN already sources env.sh"
        [ "$FOUND_IN" = "$HOME/.bashrc.ext" ] && \
            warn "  that is a deprecated .ext file -- see the note below"
    else
        warn "$FOUND_IN has an hpcenvs block, but pointing somewhere else --"
        warn "  edit it by hand, or run --undo and re-run"
    fi
elif [ "$CHECK" = 1 ]; then
    warn "$RC does not source env.sh (run without --check to add it)"
else
    {
        echo ""
        echo "$MARK"
        echo "# Added by setup-user.sh. Safe to source anywhere: it is silent,"
        echo "# idempotent, and does nothing off Perlmutter."
        echo "if [ -r \"$ENVSH\" ]; then . \"$ENVSH\"; fi"
        echo "$ENDMARK"
    } >> "$RC"
    act "added env.sh to $RC"
    act "run '. $RC' or open a new shell to pick it up now"
fi

# Flag the legacy files rather than working around them forever: NERSC asks
# that their contents move into the standard dotfiles and the .ext files go.
for ext in "$HOME/.bashrc.ext" "$HOME/.bash_profile.ext"; do
    [ -f "$ext" ] || continue
    warn "$ext exists and is deprecated by NERSC -- move its contents into"
    warn "  the matching standard dotfile and delete it. See"
    warn "  https://docs.nersc.gov/environment/#customizing-your-shell-environment"
done
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

# Coding-agent rules: only for users who ran setup-agents.sh (its marker is in
# either file). It names the same files setup-agents.sh writes.
if grep -qsF 'idrobolab-env agent rules >>>' \
        "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md" "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"; then
    echo
    echo "4. coding-agent rules (setup-agents.sh --check)"
    "$HELPERS/setup-agents.sh" --check | sed 's/^/  /' || warn "setup-agents.sh --check found something to do"
fi

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
