#!/bin/bash
# make-vscode-workspace.sh — write a VS Code workspace file with your home directory,
# your $SCRATCH and any project folders you name, for use over Remote - SSH.
# Run it on a login node:
#
#     ~/idrobolab-env/perlmutter/helpers/make-vscode-workspace.sh [-o FILE] [DIR ...]
#
# It writes FILE (default ~/perlmutter.code-workspace) and nothing else. Open that file
# with File > Open Workspace from File... instead of opening a bare folder.
#
# Folders, in this order: $HOME, each DIR (in the order given), $SCRATCH. Home comes
# first on purpose: the Claude Code extension scopes its working directory, its memory
# and its list of past sessions to the FIRST folder of the window, so every window
# opened from this file shows the same sessions. A bare folder gives its own list.
#
# Shared filesystems are protected: the workspace tells VS Code not to watch DIR or
# $SCRATCH (the explorer then needs its refresh button to show new files), not to watch
# the caches under $HOME, and not to follow symlinks when searching. Re-run the script
# after changing the folders; it overwrites FILE.
set -euo pipefail

out=$HOME/perlmutter.code-workspace
case "${1:-}" in
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -o) [ $# -ge 2 ] || { echo "-o needs a file name" >&2; exit 1; }; out=$2; shift 2 ;;
esac

# Quote $1 as a JSON string.
js() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

folders=("$HOME")
for d in "$@"; do folders+=("${d%/}"); done
scratch=${SCRATCH:-${PSCRATCH:-}}
if [ -n "$scratch" ]; then folders+=("${scratch%/}"); fi

# Reject missing folders and drop repeats (by resolved path).
list=() seen=" "
for d in "${folders[@]}"; do
    [ -d "$d" ] || { echo "not a directory: $d" >&2; exit 1; }
    real=$(readlink -f "$d")
    case "$seen" in *" $real "*) continue ;; esac
    seen+="$real "
    list+=("$d")
done

{
    echo '{'
    echo '  "folders": ['
    for i in "${!list[@]}"; do
        d=${list[i]}
        name=home sep=,
        [ "$i" -gt 0 ] && name=$(basename "$d")
        [ -n "$scratch" ] && [ "$d" = "${scratch%/}" ] && name=scratch
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
