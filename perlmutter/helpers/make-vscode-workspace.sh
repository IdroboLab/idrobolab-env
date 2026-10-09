#!/bin/bash
# make-vscode-workspace.sh — write the group's VS Code workspace file: your home
# directory, the project's CFS tree and your $SCRATCH in one window, for use over
# Remote - SSH. setup-user.sh runs it once; run it by hand to change the folders:
#
#     ~/idrobolab-env/perlmutter/helpers/make-vscode-workspace.sh [-o FILE] [DIR ...]
#     ~/idrobolab-env/perlmutter/helpers/make-vscode-workspace.sh --if-absent
#
# It writes FILE (default ~/perlmutter.code-workspace) and nothing else, replacing it
# if it exists; --if-absent leaves an existing file alone. Open the file with
# File > Open Workspace from File... instead of opening a bare folder.
#
# Folders, in this order: $HOME, /global/cfs/cdirs/$NERSC_PROJECT (<project> unless
# NERSC_PROJECT is set), each DIR (in the order given), $SCRATCH. Home comes first on
# purpose: the Claude Code extension scopes its working directory, its memory and its
# list of past sessions to the FIRST folder of the window, so every window opened from
# this file shows the same sessions. A bare folder gives its own list.
#
# The workspace tells VS Code not to watch the CFS tree, any DIR or $SCRATCH (the
# explorer then needs its refresh button to show new files), nor the cache folders under
# $HOME, and not to follow symlinks when searching. It does not stop Find in Files or
# Quick Open from walking those folders when used.
set -euo pipefail

out=$HOME/perlmutter.code-workspace
if_absent=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
        -o) [ $# -ge 2 ] || { echo "-o needs a file name" >&2; exit 1; }; out=$2; shift 2 ;;
        --if-absent) if_absent=1; shift ;;
        -*) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
        *) break ;;
    esac
done
if [ "$if_absent" = 1 ] && [ -e "$out" ]; then echo "$out exists, left alone"; exit 0; fi
[ -d "$(dirname -- "$out")" ] || { echo "no such directory for $out" >&2; exit 1; }

# Quote $1 as a JSON string.
js() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

folders=("$HOME")
cfs=/global/cfs/cdirs/${NERSC_PROJECT:-<project>}
if [ -d "$cfs" ]; then folders+=("$cfs"); fi
# The folders you name are written as absolute paths: VS Code resolves a relative one
# against the workspace file, not against where you ran this.
for d in "$@"; do folders+=("$(realpath -s -- "$d")"); done
scratch=${SCRATCH:-${PSCRATCH:-}}
if [ -n "$scratch" ] && [ -d "$scratch" ]; then scratch=${scratch%/}; folders+=("$scratch"); else scratch=; fi

# Reject missing folders and drop repeats (by resolved path).
nl=$'\n'
list=() seen=$nl
for d in "${folders[@]}"; do
    [ -d "$d" ] || { echo "not a directory: $d" >&2; exit 1; }
    real=$(readlink -f "$d")
    case "$seen" in *"$nl$real$nl"*) continue ;; esac
    seen+="$real$nl"
    list+=("$d")
done

{
    echo '{'
    echo '  "folders": ['
    for i in "${!list[@]}"; do
        d=${list[i]}
        name=home sep=,
        [ "$i" -gt 0 ] && name=$(basename "$d")
        [ -n "$scratch" ] && [ "$d" = "$scratch" ] && name=scratch
        [ "$i" -eq $((${#list[@]} - 1)) ] && sep=
        echo "    { \"path\": $(js "$d"), \"name\": $(js "$name") }$sep"
    done
    echo '  ],'
    echo '  "settings": {'
    echo '    "search.followSymlinks": false,'
    echo '    "files.watcherExclude": {'
    for p in '**/.git/objects/**' '**/node_modules/**' '**/.venv/**' '**/__pycache__/**' \
             '**/.cache/**' '**/.conda/**' '**/.local/**' '**/.cupy/**' '**/.nv/**' \
             '**/.vscode-server/**' '**/.claude/projects/**'; do
        echo "      $(js "$p"): true,"
    done
    # Every folder after home: its path as given and as resolved.
    for i in "${!list[@]}"; do
        [ "$i" -eq 0 ] && continue
        echo "      $(js "${list[i]}/**"): true,"
        real=$(readlink -f "${list[i]}")
        if [ "$real" != "${list[i]}" ]; then echo "      $(js "$real/**"): true,"; fi
    done
    echo '      "**/.git/subtree-cache/**": true'
    echo '    }'
    echo '  }'
    echo '}'
} > "$out"

echo "wrote $out:"
printf '  %s\n' "${list[@]}"
