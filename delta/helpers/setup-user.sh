#!/bin/bash
# setup-user.sh: one-shot per-user setup for the idrobolab stack on Delta.
# Idempotent: re-run it after the repo changes, or any time you are unsure.
#
# Run it on a login node, from your own clone of idrobolab-env:
#
#     ~/idrobolab-env/delta/helpers/setup-user.sh                   # do it
#     ~/idrobolab-env/delta/helpers/setup-user.sh --project NAME    # name the Delta project
#     ~/idrobolab-env/delta/helpers/setup-user.sh --check           # report only, change nothing
#     ~/idrobolab-env/delta/helpers/setup-user.sh --undo            # remove the block it added
#
# What it does:
#   1. finds your Delta project, the <project> of your <project>-delta-cpu and
#      <project>-delta-gpu accounts (--project, else $DELTA_PROJECT, else your
#      delta_<project> group, if you are in exactly one)
#   2. adds a block to ~/.bashrc that exports DELTA_PROJECT and sources env.sh
#      from the clone the script runs from
#   3. creates your apptainer cache directory on your personal scratch
#   4. reports what silently breaks later: lines in ~/.bashrc that override
#      env.sh, apptainer or uv missing, no shared uv cache, no image fetched yet
#
# A block written from another checkout or for another project is reported, not
# replaced: --undo, then run it again.
set -euo pipefail

CHECK=0 UNDO=0 PROJ=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   CHECK=1; shift ;;
        --undo)    UNDO=1;  shift ;;
        --project) [ $# -ge 2 ] || { echo "--project needs a name" >&2; exit 1; }
                   PROJ=$2; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
done

HELPERS=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENVSH="$(dirname "$HELPERS")/env.sh"
RC="$HOME/.bashrc"
MARK="# >>> idrobolab-env (delta) >>>"
ENDMARK="# <<< idrobolab-env (delta) <<<"

WARNINGS=0
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
act()  { printf '  did   %s\n' "$*"; }

# --- undo: remove our block, leave everything else alone ---------------------
if [ "$UNDO" = 1 ]; then
    if [ -f "$RC" ] && grep -qxF "$MARK" "$RC"; then
        cp -p "$RC" "$RC.idrobolab-env-backup"
        sed -i --follow-symlinks "/^${MARK}\$/,/^${ENDMARK}\$/d" "$RC"
        # ...and the blank lines at the end of the file, which removes the one
        # written before the block when the block was the last thing added.
        sed -i --follow-symlinks -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$RC"
        echo ">> removed the idrobolab-env block from $RC (backup: $RC.idrobolab-env-backup)"
        echo "   Open a new shell; the current one still has env.sh applied."
    else
        echo ">> no idrobolab-env block found in $RC"
    fi
    exit 0
fi

echo "idrobolab-env user setup: Delta"
[ "$CHECK" = 1 ] && echo "(--check: reporting only, nothing will be changed)"
echo

# --- 1. project --------------------------------------------------------------
echo "1. Delta project"
if [ -z "$PROJ" ] && [ -n "${DELTA_PROJECT:-}" ]; then
    PROJ=$DELTA_PROJECT
fi
if [ -z "$PROJ" ]; then
    # Members of a Delta project are in the Unix group delta_<project>.
    found=$(id -Gn | tr ' ' '\n' | sed -n 's/^delta_//p')
    if [ "$(printf '%s\n' "$found" | grep -c .)" = 1 ]; then
        PROJ=$found
    elif [ -n "$found" ]; then
        warn "you are in several Delta projects; pick one with --project NAME:"
        printf '%s\n' "$found" | sed 's/^/          /'
    fi
fi
if [ -z "$PROJ" ]; then
    warn "no Delta project: run with --project NAME (see the \`accounts\` command)"
    echo
    echo "$WARNINGS warning(s) above."
    exit 1
fi
# The name is written into ~/.bashrc and becomes part of two paths.
case "$PROJ" in
    *[!A-Za-z0-9_-]*) echo "not a project name: $PROJ" >&2; exit 1 ;;
esac
ok "$PROJ"
echo

# --- 2. shell startup --------------------------------------------------------
echo "2. shell startup"
if [ -f "$RC" ] && grep -qxF "$MARK" "$RC"; then
    if grep -qxF "export DELTA_PROJECT=$PROJ" "$RC" && grep -qF "$ENVSH" "$RC"; then
        ok "$RC already exports DELTA_PROJECT and sources env.sh"
    else
        warn "$RC has an idrobolab-env block for another project or checkout:"
        warn "  edit it by hand, or run --undo and re-run"
    fi
elif [ "$CHECK" = 1 ]; then
    warn "$RC has no idrobolab-env block (run without --check to add it)"
else
    {
        echo ""
        echo "$MARK"
        echo "# Added by setup-user.sh. Safe to source anywhere: env.sh is silent,"
        echo "# idempotent, and does nothing off Delta."
        echo "export DELTA_PROJECT=$PROJ"
        echo "if [ -r \"$ENVSH\" ]; then . \"$ENVSH\"; fi"
        echo "$ENDMARK"
    } >> "$RC"
    act "added the block to $RC"
    act "run '. $RC' or open a new shell to pick it up now"
fi
# env.sh keeps a value that is already set, so an assignment elsewhere in
# ~/.bashrc decides instead of it.
if [ -f "$RC" ]; then
    own=$(sed "/^${MARK}\$/,/^${ENDMARK}\$/d" "$RC" \
          | grep -nE '^[[:space:]]*(export[[:space:]]+)?(SCRATCH_BASE|PROJECTS_BASE|APPTAINER_CACHEDIR|UV_CACHE_DIR|UV_LINK_MODE)=' || true)
    if [ -n "$own" ]; then
        warn "$RC sets these itself, and env.sh keeps a value that is already set;"
        warn "  remove the lines to let env.sh decide:"
        printf '%s\n' "$own" | sed 's/^/          /'
    fi
fi
echo

# --- 3. the things that break later -----------------------------------------
echo "3. checks"
# Judge env.sh by what it sets for this project alone, not by what the calling
# shell already carries.
unset SCRATCH_BASE PROJECTS_BASE APPTAINER_CACHEDIR UV_CACHE_DIR UV_LINK_MODE
DELTA_PROJECT=$PROJ
# shellcheck source=../env.sh
. "$ENVSH"
if [ -z "${SCRATCH_BASE:-}" ]; then
    warn "env.sh set nothing: /scratch/$PROJ is not a directory here (wrong project name,"
    warn "  or this is not Delta)"
    echo
    echo "$WARNINGS warning(s) above."
    exit 1
fi
ok "SCRATCH_BASE=$SCRATCH_BASE  PROJECTS_BASE=$PROJECTS_BASE"

CACHE=$APPTAINER_CACHEDIR
if [ -d "$CACHE" ]; then
    ok "apptainer cache directory exists: $CACHE"
elif [ "$CHECK" = 1 ]; then
    warn "no apptainer cache directory yet: $CACHE (run without --check to create it)"
elif mkdir -p "$CACHE"; then
    act "created $CACHE"
else
    warn "could not create $CACHE"
fi

if command -v apptainer >/dev/null 2>&1; then
    ok "apptainer is on PATH"
else
    warn "apptainer is not on PATH (are you on a login node?)"
fi

if command -v uv >/dev/null 2>&1; then
    ok "uv is on PATH: $(command -v uv)"
else
    warn "uv is not on PATH (an admin installs it into $PROJECTS_BASE/software/bin:"
    warn "  docs/delta/README.md)"
fi

if [ "$UV_CACHE_DIR" = "$SCRATCH_BASE/uv-cache" ]; then
    ok "uv uses the project's shared cache: $UV_CACHE_DIR"
else
    warn "no shared uv cache at $SCRATCH_BASE/uv-cache that you can write to; uv uses"
    warn "  $UV_CACHE_DIR (an admin creates the shared one: docs/delta/README.md)"
fi

SIF="$PROJECTS_BASE/software/containers/idrobolab.sif"
if [ -f "$SIF" ]; then
    ok "image: $SIF"
else
    warn "no image at $SIF yet: see $(dirname "$HELPERS")/get-image.sh"
fi

echo
if [ "$WARNINGS" -eq 0 ]; then
    echo "All good."
else
    echo "$WARNINGS warning(s) above."
fi
