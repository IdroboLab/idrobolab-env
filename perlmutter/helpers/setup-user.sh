#!/bin/bash
# setup-user.sh — one-shot per-user setup for this project on Perlmutter.
# Idempotent: re-run it after the repo changes, or any time you are unsure.
#
# Run it from your own clone of idrobolab-env:
#
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh           # do it
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh --check   # report only, change nothing
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh --undo    # remove the block and the GitHub e-mail rule
#         (a startup file is left untouched, exit 1, unless its block's two marker lines are intact)
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh --github-email ADDRESS
#         # commit in GitHub repositories as ADDRESS (your GitHub noreply address)
#     ~/idrobolab-env/perlmutter/helpers/setup-user.sh --vscode-workspace
#                                                               # also write the VS Code workspace
#
# The block sources env.sh from the clone the script runs from. A block written
# from another checkout is reported, not replaced: --undo, then run it again.
#
# What it does:
#   1. sources env.sh from your shell startup file (image store, aliases, PATH)
#   2. links the project's shared Jupyter kernels into your own kernel dir
#   3. checks the things that silently break later: project group membership,
#      whether the shared image store is actually readable by you, $SCRATCH
#   4. only with --vscode-workspace: writes ~/perlmutter.code-workspace for VS Code
#      (home, the project's CFS tree and $SCRATCH in one window) unless the file
#      exists; otherwise just reports whether it is there. --undo keeps the file
#   5. if you ran setup-agents.sh, shows its --check result
#   6. with --github-email, sets the address your commits in GitHub repositories
#      carry; the checks always report that address
set -euo pipefail

GHMAIL="" CHECK=0 UNDO=0 VSCODE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   CHECK=1;   shift ;;
        --github-email) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "--github-email needs an address" >&2; exit 1; }
                   GHMAIL=$2; shift 2 ;;
        --undo)    UNDO=1;    shift ;;
        --vscode-workspace) VSCODE=1; shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
done

# The clone's path as the user reaches it (/global/homes/..., not the physical
# home path), so the block keeps working if NERSC moves the home directory.
HELPERS=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../../shared/helpers/github-identity.sh
. "$(dirname "$(dirname "$HELPERS")")/shared/helpers/github-identity.sh"
if [ -n "$GHMAIL" ] && ! github_identity_valid "$GHMAIL"; then
    echo "not an e-mail address: $GHMAIL" >&2
    exit 1
fi
PERLMUTTER=$(dirname "$HELPERS")
DOCS="$(dirname "$PERLMUTTER")/docs/perlmutter"
PROJECT="${NERSC_PROJECT:-<project>}"
SHARED_JUPYTER="${IDROBOLAB_ENV_SHARED_JUPYTER:-/global/common/software/${PROJECT}/share/jupyter}"

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
act()  { printf '  \033[36mdid\033[0m   %s\n' "$*"; }
WARNINGS=0

if [ "$CHECK" = 1 ] && [ "$UNDO" = 1 ]; then
    echo "--check and --undo exclude each other" >&2
    exit 1
fi

# True when FILE holds no START line, or one START line with one END line below
# it. With anything else the range delete below would cut to the end of the file.
block_is_whole() {   # START END FILE
    local starts ends
    starts=$(grep -nxF "$1" "$3" | cut -d: -f1 || true)
    ends=$(grep -nxF "$2" "$3" | cut -d: -f1 || true)
    [ -z "$starts$ends" ] && return 0
    case "$starts:$ends" in
        *[!0-9:]*|:*|*:) return 1 ;;
    esac
    [ "$starts" -lt "$ends" ]
}
# --- undo: remove our block, leave everything else alone ---------------------
# Only the marked block, never the whole file: people put their own things in
# these files, and a startup file is not ours to reset.
if [ "$UNDO" = 1 ]; then
    github_identity_undo
    removed=0 refused=0
    for rc in "$HOME/.bashrc.ext" "$HOME/.bashrc"; do
        [ -f "$rc" ] || continue
        # Whole lines only, as the removal below matches them: a marker with
        # trailing whitespace or inside a longer line is not ours to remove.
        grep -qxF -e "# >>> idrobolab-env (${PROJECT}) >>>" -e "# >>> hpcenvs (${PROJECT}) >>>" "$rc" || continue
        if ! block_is_whole "# >>> idrobolab-env (${PROJECT}) >>>" "# <<< idrobolab-env (${PROJECT}) <<<" "$rc" \
           || ! block_is_whole "# >>> hpcenvs (${PROJECT}) >>>" "# <<< hpcenvs (${PROJECT}) <<<" "$rc"; then
            echo "$rc: the idrobolab-env (or hpcenvs) markers are not one start line followed by one" >&2
            echo "  end line; nothing changed there. Remove the block by hand." >&2
            refused=1
            continue
        fi
        cp -p "$rc" "$rc.idrobolab-env-backup"
        # Blocks written before the repo was renamed carry the name hpcenvs.
        sed -i --follow-symlinks \
            -e "/^# >>> idrobolab-env (${PROJECT}) >>>$/,/^# <<< idrobolab-env (${PROJECT}) <<<$/d" \
            -e "/^# >>> hpcenvs (${PROJECT}) >>>$/,/^# <<< hpcenvs (${PROJECT}) <<<$/d" "$rc"
        # ...including the blank line we wrote before it, so the file comes back
        # byte-identical when ours was the only addition.
        sed -i --follow-symlinks -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$rc"
        echo ">> removed the idrobolab-env block from $rc (backup: $rc.idrobolab-env-backup)"
        removed=1
    done
    if [ "$removed" = 1 ]; then
        echo "   Open a new shell; the current one still has env.sh applied."
    elif [ "$refused" = 0 ]; then
        echo ">> no idrobolab-env block found in ~/.bashrc.ext or ~/.bashrc"
    fi
    exit "$refused"
fi

echo "idrobolab-env user setup — project $PROJECT"
[ "$CHECK" = 1 ] && echo "(--check: reporting only, nothing will be changed)"
echo

# The address commits in GitHub repositories carry. Set here, before anything
# below can stop the script: it does not depend on the cluster or the project.
if [ -n "$GHMAIL" ] && [ "$CHECK" = 0 ]; then
    github_identity_set "$GHMAIL"
    act "GitHub repositories now commit as $GHMAIL (~/.gitconfig-github)"
    echo
fi

# --- 1. shell startup --------------------------------------------------------
# ~/.bashrc, per NERSC's current guidance: the .bashrc.ext / .bash_profile.ext
# split is deprecated and the standard dotfiles are yours to edit.
# https://docs.nersc.gov/environment/#customizing-your-shell-environment
echo "1. shell startup"
RC="$HOME/.bashrc"
MARK="# >>> idrobolab-env (${PROJECT}) >>>"
ENDMARK="# <<< idrobolab-env (${PROJECT}) <<<"
OLDMARK="# >>> hpcenvs (${PROJECT}) >>>"   # written before the repo was renamed
ENVSH="${PERLMUTTER}/env.sh"

# An account created before February 2020 may still have a .ext file, and an
# earlier version of this script wrote the block there, and earlier versions
# marked it hpcenvs. Find it wherever it is and under either name, so a re-run
# neither duplicates the block nor reports it missing. A marker counts only as a
# whole line, as --undo matches it; a line that merely contains one (trailing
# whitespace, a carriage return, text around it) is reported, since --undo
# leaves it alone and appending a second block next to it would hide it.
FOUND_IN="" DAMAGED_IN=""
for rc in "$RC" "$HOME/.bashrc.ext"; do
    [ -f "$rc" ] || continue
    grep -qxF -e "$MARK" -e "$OLDMARK" "$rc" && { FOUND_IN=$rc; break; }
    grep -qF -e "$MARK" -e "$OLDMARK" "$rc" && [ -z "$DAMAGED_IN" ] && DAMAGED_IN=$rc
done
# A start line without its one end line below is damaged too: --undo refuses it.
if [ -n "$FOUND_IN" ] && { ! block_is_whole "$MARK" "$ENDMARK" "$FOUND_IN" \
        || ! block_is_whole "$OLDMARK" "# <<< hpcenvs (${PROJECT}) <<<" "$FOUND_IN"; }; then
    DAMAGED_IN=$FOUND_IN FOUND_IN=""
fi

if [ -n "$FOUND_IN" ]; then
    if grep -qF "$ENVSH" "$FOUND_IN"; then
        ok "$FOUND_IN already sources env.sh"
        if grep -qxF "$OLDMARK" "$FOUND_IN"; then
            if [ "$CHECK" = 1 ]; then
                warn "$FOUND_IN marks the block hpcenvs (run without --check to rename it)"
            else
                cp -p "$FOUND_IN" "$FOUND_IN.idrobolab-env-backup"
                sed -i --follow-symlinks \
                    -e "s/^# >>> hpcenvs (${PROJECT}) >>>\$/${MARK}/" \
                    -e "s/^# <<< hpcenvs (${PROJECT}) <<<\$/${ENDMARK}/" "$FOUND_IN"
                act "renamed the hpcenvs markers in $FOUND_IN (backup: $FOUND_IN.idrobolab-env-backup)"
            fi
        fi
        [ "$FOUND_IN" = "$HOME/.bashrc.ext" ] && \
            warn "  that is a deprecated .ext file -- see the note below"
    else
        warn "$FOUND_IN has an idrobolab-env block, but pointing somewhere else --"
        warn "  edit it by hand, or run --undo and re-run"
    fi
elif [ -n "$DAMAGED_IN" ]; then
    warn "$DAMAGED_IN has an idrobolab-env block whose marker lines are not exactly one start"
    warn "  line and one end line below it (trailing spaces, a Windows line ending, extra text,"
    warn "  a missing line): nothing added, and --undo will not remove that block -- repair the"
    warn "  marker lines or delete the block by hand"
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
        # Captured, then matched with a here-string: under pipefail a pipe into
        # grep -q fails whenever podman-hpc takes SIGPIPE after the first match.
        images=$(podman-hpc images 2>/dev/null || true)
        if grep -qE 'idrobolab' <<<"$images"; then
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

# The address commits in GitHub repositories carry.
if [ -n "$GHMAIL" ] && [ "$CHECK" = 1 ]; then
    warn "--github-email is not applied with --check"
fi
github_identity_report

echo
echo "4. VS Code workspace"
WORKSPACE="$HOME/perlmutter.code-workspace"
if [ -e "$WORKSPACE" ]; then
    ok "$WORKSPACE exists (make-vscode-workspace.sh rewrites it; setup-user.sh never does)"
elif [ "$VSCODE" = 1 ] && [ "$CHECK" = 0 ]; then
    if "$HELPERS/make-vscode-workspace.sh" --if-absent | sed 's/^/  /'; then
        act "open it in VS Code with File > Open Workspace from File ($DOCS/11-vscode.md)"
    else
        warn "could not write $WORKSPACE (see above); run $HELPERS/make-vscode-workspace.sh by hand"
    fi
else
    ok "no VS Code workspace file (optional: run setup-user.sh --vscode-workspace)"
fi

# Coding-agent rules: only for users who ran setup-agents.sh (its marker is in
# either file). It names the same files setup-agents.sh writes.
if grep -qsF 'idrobolab-env agent rules >>>' \
        "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md" "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"; then
    echo
    echo "5. coding-agent rules (setup-agents.sh --check)"
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
echo "  * notebooks:        $DOCS/reference/jupyter.md"
echo "  * batch templates:  $PERLMUTTER/jobs/README.md"
echo "  * container notes:  $DOCS/reference/podman-hpc.md"
echo "  * from a laptop, set up sshproxy so ssh does not prompt every time:"
echo "    https://docs.nersc.gov/connect/mfa/#sshproxy"
