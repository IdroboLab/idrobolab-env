#!/bin/bash
# setup-user.sh: one-shot per-user setup for the idrobolab stack on Delta.
# Idempotent: re-run it after the repo changes, or any time you are unsure.
#
# Run it on a login node, from your own clone of idrobolab-env:
#
#     ~/idrobolab-env/delta/helpers/setup-user.sh                   # do it
#     ~/idrobolab-env/delta/helpers/setup-user.sh --project NAME    # name the Delta project
#     ~/idrobolab-env/delta/helpers/setup-user.sh --check           # report only, change nothing
#     ~/idrobolab-env/delta/helpers/setup-user.sh --undo            # remove the block and the GitHub e-mail rule
#     ~/idrobolab-env/delta/helpers/setup-user.sh --github-email ADDRESS
#         # commit in GitHub repositories as ADDRESS (your GitHub noreply address)
#
# What it does:
#   1. finds your Delta project, the <project> of your <project>-delta-cpu and
#      <project>-delta-gpu accounts (--project, else $DELTA_PROJECT, else your
#      delta_<project> group, if exactly one of your delta_* groups has a
#      scratch directory), and stops unless env.sh finds its scratch directory
#   2. adds a block to ~/.bashrc that exports DELTA_PROJECT and sources env.sh
#      from the clone the script runs from
#   3. creates your apptainer cache directory on your personal scratch
#   4. reports what silently breaks later: lines in ~/.bashrc that override
#      env.sh, apptainer or uv missing, no shared uv cache, no image fetched yet
#   5. with --github-email, sets the address your commits in GitHub repositories
#      carry; the checks always report that address
#
# A block written from another checkout or for another project is reported, not
# replaced: --undo, then run it again.
set -euo pipefail

HELPERS=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../../core/shell/setup-user-common.sh
. "$(dirname "$(dirname "$HELPERS")")/core/shell/setup-user-common.sh"
SETUP_USER_NAME=idrobolab-env
SETUP_USER_PROJECT_NOUN="a name"
setup_user_parse_args "$@"
setup_user_validate
ENVSH="$(dirname "$HELPERS")/env.sh"
RC="$HOME/.bashrc"
MARK="# >>> idrobolab-env (delta) >>>"
ENDMARK="# <<< idrobolab-env (delta) <<<"

# --- undo: remove our block, leave everything else alone ---------------------
if [ "$UNDO" = 1 ]; then setup_user_undo; fi

setup_user_begin "idrobolab-env user setup: Delta"

# --- 1. project --------------------------------------------------------------
echo "1. Delta project"
if [ -z "$PROJ" ] && [ -n "${DELTA_PROJECT:-}" ]; then
    PROJ=$DELTA_PROJECT
fi
if [ -z "$PROJ" ]; then
    # Members of a Delta project are in the Unix group delta_<project>. Delta
    # has other delta_* groups too (delta_active_users), so a group counts only
    # when env.sh finds a scratch directory for its name.
    found=$(for g in $(id -Gn | tr ' ' '\n' | sed -n 's/^delta_//p'); do
                case "$g" in *[!A-Za-z0-9_-]*) continue ;; esac
                if (unset SCRATCH_BASE; DELTA_PROJECT=$g; . "$ENVSH"; [ -n "${SCRATCH_BASE:-}" ]); then
                    echo "$g"
                fi
            done)
    if [ "$(printf '%s\n' "$found" | grep -c .)" = 1 ]; then
        PROJ=$found
    elif [ -n "$found" ]; then
        warn "you are in several Delta projects; pick one with --project NAME:"
        printf '%s\n' "$found" | sed 's/^/          /'
    fi
fi
if [ -z "$PROJ" ]; then
    warn "no Delta project: run with --project NAME (see the \`accounts\` command)"
    setup_user_stop
fi
# The name is written into ~/.bashrc and becomes part of two paths.
case "$PROJ" in
    *[!A-Za-z0-9_-]*) echo "not a project name: $PROJ" >&2; exit 1 ;;
esac
# env.sh is the judge of the name: it sets nothing unless the project's scratch
# directory exists. Judged by what it sets for this project alone, not by what
# the calling shell already carries, and before anything is written.
unset SCRATCH_BASE PROJECTS_BASE APPTAINER_CACHEDIR UV_CACHE_DIR UV_LINK_MODE
DELTA_PROJECT=$PROJ
# shellcheck source=../env.sh
. "$ENVSH"
if [ -z "${SCRATCH_BASE:-}" ]; then
    warn "env.sh sets nothing for $PROJ: /scratch/$PROJ is not a directory here (wrong"
    more "project name, or this is not Delta); ~/.bashrc unchanged"
    setup_user_stop
fi
ok "$PROJ  (SCRATCH_BASE=$SCRATCH_BASE  PROJECTS_BASE=$PROJECTS_BASE)"
echo

# --- 2. shell startup --------------------------------------------------------
echo "2. shell startup"
if [ -f "$RC" ] && grep -qxF "$MARK" "$RC"; then
    if grep -qxF "export DELTA_PROJECT=$PROJ" "$RC" && grep -qF "$ENVSH" "$RC"; then
        ok "$RC already exports DELTA_PROJECT and sources env.sh"
    else
        warn "$RC has an idrobolab-env block for another project or checkout:"
        more "edit it by hand, or run --undo and re-run"
    fi
elif [ "$CHECK" = 1 ]; then
    warn "$RC has no idrobolab-env block (run without --check to add it)"
else
    setup_user_add_block DELTA_PROJECT "$PROJ" Delta
fi
# env.sh keeps a value that is already set, so an assignment elsewhere in
# ~/.bashrc decides instead of it.
if [ -f "$RC" ]; then
    own=$(sed "/^${MARK}\$/,/^${ENDMARK}\$/d" "$RC" \
          | grep -nE '^[[:space:]]*(export[[:space:]]+)?(SCRATCH_BASE|PROJECTS_BASE|APPTAINER_CACHEDIR|UV_CACHE_DIR|UV_LINK_MODE)=' || true)
    if [ -n "$own" ]; then
        warn "$RC sets these itself, and env.sh keeps a value that is already set;"
        more "remove the lines to let env.sh decide:"
        printf '%s\n' "$own" | sed 's/^/          /'
    fi
fi
echo

# --- 3. the things that break later -----------------------------------------
echo "3. checks"
CACHE=$APPTAINER_CACHEDIR
setup_user_cache_dir "$CACHE"

setup_user_check_apptainer

if command -v uv >/dev/null 2>&1; then
    ok "uv is on PATH: $(command -v uv)"
else
    warn "uv is not on PATH (an admin installs it into $PROJECTS_BASE/software/bin:"
    more "docs/delta/README.md)"
fi

if [ "$UV_CACHE_DIR" = "$SCRATCH_BASE/uv-cache" ]; then
    ok "uv uses the project's shared cache: $UV_CACHE_DIR"
else
    warn "no shared uv cache at $SCRATCH_BASE/uv-cache that you can write to; uv uses"
    more "$UV_CACHE_DIR (an admin creates the shared one: docs/delta/README.md)"
fi

# The address commits in GitHub repositories carry.
setup_user_github_report

SIF="$PROJECTS_BASE/software/containers/idrobolab.sif"
if [ -f "$SIF" ]; then
    ok "image: $SIF"
else
    warn "no image at $SIF yet: see $(dirname "$HELPERS")/get-image.sh"
fi

setup_user_summary
