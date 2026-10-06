#!/bin/bash
# setup-agents.sh — make Claude Code and Codex follow NERSC's baseline and the
# group's rules. Idempotent: re-run it after every `git pull` of this repo.
#
# Run it from your own clone of idrobolab-env:
#
#     ~/idrobolab-env/perlmutter/helpers/setup-agents.sh           # do it
#     ~/idrobolab-env/perlmutter/helpers/setup-agents.sh --check   # report only, change nothing
#     ~/idrobolab-env/perlmutter/helpers/setup-agents.sh --undo    # remove what it added
#
# The sources are in perlmutter/agents/: nersc/ (NERSC's files, vendored) and
# group.md (the group's rules).
#
#   Claude Code  ${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md gets a marked block
#                at the top that imports both files from this clone, so a
#                `git pull` updates them. Your own text stays below it. If the
#                file lies inside a git work tree it is left alone and the
#                lines to add are printed.
#   Codex        ${CODEX_HOME:-~/.codex}/AGENTS.md has no imports, so a copy of
#                both files is written between markers, followed by a
#                "## Local additions" heading and your own text. Re-run after
#                a `git pull`; --check says when the copy is stale.
#
# --check exits 1 when something needs action. --undo removes the block or the
# managed part and keeps your text.
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

umask 077   # NERSC: these files and directories are for you alone

# The clone's path as the user reaches it, as in setup-user.sh.
HELPERS=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENTS=$(dirname "$HELPERS")/agents
NERSC_CLAUDE=$AGENTS/nersc/claude/.claude/CLAUDE.md
NERSC_CODEX=$AGENTS/nersc/codex/.codex/AGENTS.md
GROUP=$AGENTS/group.md

CLAUDE_FILE=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md
CODEX_FILE=${CODEX_HOME:-$HOME/.codex}/AGENTS.md

CL_BEGIN='# >>> idrobolab-env agent rules >>>'
CL_END='# <<< idrobolab-env agent rules <<<'
CX_BEGIN='<!-- >>> idrobolab-env agent rules >>> -->'
CX_END='<!-- <<< idrobolab-env agent rules <<< -->'
HEADING='## Local additions'
MAX_BYTES=32768   # Codex reads at most 32 KiB of AGENTS.md text in total

for f in "$NERSC_CLAUDE" "$NERSC_CODEX" "$GROUP"; do
    [ -f "$f" ] || { echo "missing $f: is this a complete clone?" >&2; exit 1; }
done

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
act()  { printf '  \033[36mdid\033[0m   %s\n' "$*"; }
WARNINGS=0

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# A path with $HOME written as ~, for Claude's @ imports.
tilde() { case "$1" in "$HOME"/*) printf '%s/%s' '~' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# $1 = a file we want to write: does it lie inside a git work tree? Other
# sessions load a tracked file, so we do not edit one.
in_git_tree() {
    local d
    d=$(dirname "$1")
    while [ ! -d "$d" ]; do d=$(dirname "$d"); done
    [ "$(git -C "$d" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]
}

# stdin -> the block between two marker lines, markers included.
block_of() { awk -v b="$1" -v e="$2" '$0 == b {p = 1} p {print} $0 == e {p = 0}'; }

# stdin -> everything except that block and the one blank line after it.
without_block() {
    awk -v b="$1" -v e="$2" '
        skip { if ($0 == e) { skip = 0; drop = 1 } next }
        $0 == b { skip = 1; next }
        drop { drop = 0; if ($0 == "") next }
        { print }'
}

# $1 = a directory we are about to create a file in
make_dir() { [ -d "$1" ] || { mkdir -p "$1"; chmod go-rwx "$1"; }; }

# --- Claude Code -------------------------------------------------------------
claude_block() {
    echo "$CL_BEGIN"
    echo "# Added by setup-agents.sh (idrobolab-env); your own text goes below this block."
    echo "@$(tilde "$NERSC_CLAUDE")"
    echo "@$(tilde "$GROUP")"
    echo "$CL_END"
}

claude() {
    echo "Claude Code: $CLAUDE_FILE"
    local want have=""
    want=$(claude_block)
    [ -f "$CLAUDE_FILE" ] && have=$(block_of "$CL_BEGIN" "$CL_END" < "$CLAUDE_FILE")

    if [ "$UNDO" = 1 ]; then
        if [ -z "$have" ]; then
            ok "no idrobolab-env block to remove"
        elif in_git_tree "$CLAUDE_FILE"; then
            warn "lies inside a git work tree, so it is not changed: delete the block from"
            warn "  '$CL_BEGIN' to '$CL_END' by hand"
        else
            without_block "$CL_BEGIN" "$CL_END" < "$CLAUDE_FILE" > "$TMPD/claude"
            cat "$TMPD/claude" > "$CLAUDE_FILE"
            act "removed the block (your own text is kept)"
        fi
        return
    fi

    if [ -n "$have" ]; then
        if [ "$have" = "$want" ]; then
            ok "imports NERSC's baseline and the group rules"
        else
            warn "has an idrobolab-env block pointing somewhere else (another clone?):"
            warn "  edit it by hand, or run --undo and re-run"
        fi
    elif in_git_tree "$CLAUDE_FILE"; then
        warn "lies inside a git work tree, so it is not changed: add these lines at the top by hand"
        printf '%s\n' "$want" | sed 's/^/        /'
    elif [ "$CHECK" = 1 ]; then
        warn "not set up (run without --check)"
    else
        make_dir "$(dirname "$CLAUDE_FILE")"
        { printf '%s\n' "$want"; if [ -s "$CLAUDE_FILE" ]; then echo; cat "$CLAUDE_FILE"; fi; } > "$TMPD/claude"
        cat "$TMPD/claude" > "$CLAUDE_FILE"
        act "added the block to $CLAUDE_FILE; restart Claude Code to pick it up"
    fi

    if [ -f "$CLAUDE_FILE" ] && grep -qx '# NERSC Agent Guidance' "$CLAUDE_FILE"; then
        warn "the file also holds a pasted copy of NERSC's text, which now loads twice."
        warn "  Delete it by hand: from the line '# NERSC Agent Guidance' down to the line"
        warn "  above '$HEADING'; keep what you wrote below that heading."
    fi
}

# --- Codex -------------------------------------------------------------------
# stdin: the existing file. stdout: the user's own text: below the heading that
# follows our managed part, else below the first heading (a manual install of
# NERSC's file), else the whole file; without leading blank lines.
user_text() {
    awk -v e="$CX_END" -v h="$HEADING" '
        { l[NR] = $0 }
        END {
            from = 1
            for (i = 1; i <= NR; i++) if (l[i] == e) { from = i + 1; break }
            for (i = from; i <= NR; i++) if (l[i] == h) { from = i + 1; break }
            while (from <= NR && l[from] == "") from++
            for (i = from; i <= NR; i++) print l[i]
        }'
}

# $1 = file with the user's text. stdout: the whole AGENTS.md.
codex_content() {
    echo "$CX_BEGIN"
    echo "<!-- Managed by idrobolab-env/perlmutter/helpers/setup-agents.sh from perlmutter/agents/."
    echo "     Edits up to the end marker are replaced on the next run; write your own text below '$HEADING'. -->"
    sed "/^$HEADING\$/,\$d" "$NERSC_CODEX"
    cat "$GROUP"
    echo "$CX_END"
    echo
    echo "$HEADING"
    if [ -s "$1" ]; then echo; cat "$1"; fi
}

codex() {
    echo "Codex: $CODEX_FILE"
    local managed=0
    [ -f "$CODEX_FILE" ] && grep -qxF "$CX_BEGIN" "$CODEX_FILE" && managed=1

    if [ "$UNDO" = 1 ]; then
        if [ "$managed" = 0 ]; then
            ok "no managed part to remove"
        else
            without_block "$CX_BEGIN" "$CX_END" < "$CODEX_FILE" > "$TMPD/codex"
            cat "$TMPD/codex" > "$CODEX_FILE"
            act "removed the managed part (your own text, with its '$HEADING' heading, is kept)"
        fi
        return
    fi

    if [ -f "$CODEX_FILE" ]; then user_text < "$CODEX_FILE" > "$TMPD/user"; else : > "$TMPD/user"; fi
    codex_content "$TMPD/user" > "$TMPD/codex"

    if [ "$managed" = 1 ] && cmp -s "$TMPD/codex" "$CODEX_FILE"; then
        ok "up to date with NERSC's baseline and the group rules"
    elif [ "$CHECK" = 1 ]; then
        if [ "$managed" = 1 ]; then
            warn "stale: the sources in perlmutter/agents/ changed (git pull?) or the managed part was edited"
        else
            warn "not set up (run without --check)"
        fi
    else
        make_dir "$(dirname "$CODEX_FILE")"
        if [ -f "$CODEX_FILE" ] && [ "$managed" = 0 ]; then
            backup="$CODEX_FILE.bak-$(date -u +%Y%m%dT%H%M%SZ)"
            cp -p "$CODEX_FILE" "$backup"
            act "backed up the existing file to $backup"
        fi
        cat "$TMPD/codex" > "$CODEX_FILE"
        act "wrote the managed part to $CODEX_FILE; restart Codex to pick it up"
    fi

    size=$(wc -c < "$TMPD/codex")
    if [ "$size" -gt "$MAX_BYTES" ]; then
        warn "the file is $size bytes; Codex reads at most $MAX_BYTES bytes of AGENTS.md text in total"
    fi
}

# --- main --------------------------------------------------------------------
echo "idrobolab-env coding-agent setup"
[ "$CHECK" = 1 ] && echo "(--check: reporting only, nothing will be changed)"
echo
claude
echo
codex
echo
if [ "$WARNINGS" -eq 0 ]; then
    echo "All good."
else
    echo "$WARNINGS warning(s) above."
fi
[ "$CHECK" = 1 ] && [ "$WARNINGS" -gt 0 ] && exit 1
exit 0
