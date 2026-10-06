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
# group.md (the group's rules). An agent is handled only if its config directory
# exists (start it once to create it): ${CLAUDE_CONFIG_DIR:-~/.claude} and
# ${CODEX_HOME:-~/.codex}.
#
#   Claude Code  CLAUDE.md gets a marked block at the top that imports both files
#                from this clone, so a `git pull` updates them. Your own text
#                stays below it.
#   Codex        AGENTS.md has no imports, so a copy of both files is written
#                between markers, followed by a "## Local additions" heading and
#                your own text. Text outside the markers and not under that
#                heading (above the block, or between it and the heading) moves
#                below the heading, so nothing you wrote is lost. Re-run after a
#                `git pull`; --check says when the copy is stale.
#
# Before it changes an existing file it saves a timestamped copy
# (<file>.bak-<UTC time>) and prints the path. A file with unbalanced markers
# (a begin without an end, an end without a begin, a marker twice) is refused,
# in every mode, with the line numbers. A file inside a git work tree (after
# resolving symlinks) is never written: for Claude the lines to add are
# printed; use a config dir outside the tree for Codex. --undo removes the block
# or managed part and keeps everything else. --check exits 1 when something
# needs action.
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

umask 077   # NERSC: these files are for you alone

# The clone's path as the user reaches it, as in setup-user.sh.
HELPERS=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENTS=$(dirname "$HELPERS")/agents
NERSC_CLAUDE=$AGENTS/nersc/claude/.claude/CLAUDE.md
NERSC_CODEX=$AGENTS/nersc/codex/.codex/AGENTS.md
GROUP=$AGENTS/group.md

CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CLAUDE_FILE=$CLAUDE_DIR/CLAUDE.md
CODEX_FILE=$CODEX_DIR/AGENTS.md

CL_BEGIN='# >>> idrobolab-env agent rules >>>'
CL_END='# <<< idrobolab-env agent rules <<<'
CX_BEGIN='<!-- >>> idrobolab-env agent rules >>> -->'
CX_END='<!-- <<< idrobolab-env agent rules <<< -->'
HEADING='## Local additions'
MAX_BYTES=32768   # Codex reads at most 32 KiB of AGENTS.md text in total

for f in "$NERSC_CLAUDE" "$NERSC_CODEX" "$GROUP"; do
    [ -f "$f" ] || { echo "missing $f: is this a complete clone?" >&2; exit 1; }
done

# warn counts a problem; more continues its message.
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; PROBLEMS=$((PROBLEMS + 1)); }
more() { printf '        %s\n' "$*"; }
act()  { printf '  \033[36mdid\033[0m   %s\n' "$*"; }
PROBLEMS=0 REFUSED=0

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# A path with $HOME written as ~, for Claude's @ imports and messages.
tilde() { case "$1" in "$HOME"/*) printf '%s/%s' '~' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# $1 = a file we want to write: does it lie, after resolving symlinks, inside a
# git work tree? Other sessions load a tracked file, so we do not edit one.
in_git_tree() {
    local real
    real=$(readlink -f -- "$1" 2>/dev/null) || real=$1
    [ "$(git -C "$(dirname "$real")" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]
}

# $1 file, $2 begin marker, $3 end marker. Refuse (return 1) a file whose
# markers are not exactly one begin followed by one end, or absent.
markers_ok() {
    [ -f "$1" ] || return 0
    local msg
    msg=$(awk -v b="$2" -v e="$3" '
        $0 == b { nb++; if (nb == 1) lb = NR; else print "begin marker again at line " NR }
        $0 == e { ne++; if (ne == 1) le = NR; else print "end marker again at line " NR }
        END {
            if (nb && !ne) print "begin marker at line " lb " has no end marker"
            else if (ne && !nb) print "end marker at line " le " has no begin marker"
            else if (nb && le < lb) print "end marker at line " le " comes before the begin marker at line " lb
        }' "$1")
    [ -z "$msg" ] && return 0
    warn "unbalanced markers, nothing changed:"
    printf '%s\n' "$msg" | while IFS= read -r line; do more "$line"; done
    more "fix or delete the marker lines by hand, then re-run"
    REFUSED=1
    return 1
}

# $1 file, $2 begin, $3 end, $4 file with the replacement block, or "" to remove
# the block and the blank line after it. Everything else is kept as it is.
replace_region() {
    awk -v b="$2" -v e="$3" -v r="$4" '
        skip { if ($0 == e) { skip = 0; drop = (r == "") } next }
        $0 == b { skip = 1; if (r != "") while ((getline x < r) > 0) print x; next }
        drop { drop = 0; if ($0 == "") next }
        { print }' "$1"
}

# $1 target, $2 file with its new content, $3 $4 the markers. An existing target
# is saved first (never over an earlier backup) unless only the managed region
# changes; the rewrite goes through the target so a symlink stays one.
write_file() {
    local n=0 base
    BACKUP=
    if [ -f "$1" ]; then
        cmp -s "$2" "$1" && return 0
        if ! cmp -s <(replace_region "$1" "$3" "$4" "") <(replace_region "$2" "$3" "$4" ""); then
            base="$1.bak-$(date -u +%Y%m%dT%H%M%SZ)"
            BACKUP=$base
            while [ -e "$BACKUP" ]; do n=$((n + 1)); BACKUP=$base.$n; done
            cp -p "$1" "$BACKUP"
            act "saved the previous file as $BACKUP"
        fi
    fi
    cat "$2" > "$1"
}

# A pasted copy of NERSC's file next to our managed text loads twice.
pasted_warn() {
    warn "the file also holds a pasted copy of NERSC's text, which now loads twice."
    more "Delete it by hand: from the line '# NERSC Agent Guidance' to the end of the copy;"
    more "keep what you wrote."
}

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
    markers_ok "$CLAUDE_FILE" "$CL_BEGIN" "$CL_END" || return 0
    local want have="" state AGENTS_REAL
    AGENTS_REAL=$(readlink -f -- "$AGENTS")
    claude_block > "$TMPD/block"
    want=$(cat "$TMPD/block")
    [ -f "$CLAUDE_FILE" ] && have=$(awk -v b="$CL_BEGIN" -v e="$CL_END" \
        '$0 == b {p = 1} p {print} $0 == e {p = 0}' "$CLAUDE_FILE")

    if [ "$UNDO" = 1 ]; then
        if [ -z "$have" ]; then
            ok "no idrobolab-env block to remove"
        elif in_git_tree "$CLAUDE_FILE"; then
            warn "lies inside a git work tree, so it is not changed: delete the block from"
            more "'$CL_BEGIN' to '$CL_END' by hand"
        else
            replace_region "$CLAUDE_FILE" "$CL_BEGIN" "$CL_END" "" > "$TMPD/claude"
            write_file "$CLAUDE_FILE" "$TMPD/claude" "$CL_BEGIN" "$CL_END"
            act "removed the block (everything else is kept)"
        fi
        return
    fi

    # absent, ok, stale (imports from this clone, other text) or elsewhere (another clone)
    if [ -z "$have" ]; then
        state=absent
    elif [ "$have" = "$want" ]; then
        state=ok
    else
        state=stale
        while IFS= read -r line; do
            case $line in @*) case $(readlink -f -- "${line#@}") in
                "$AGENTS_REAL"/*) ;; *) state=elsewhere ;; esac ;; esac
        done <<< "${have//@\~/@$HOME}"
    fi

    case $state in
        ok)
            ok "imports NERSC's baseline and the group rules" ;;
        elsewhere)
            warn "the idrobolab-env block imports from another clone:"
            more "run --undo, then re-run from the clone you want" ;;
        *)
            if in_git_tree "$CLAUDE_FILE"; then
                warn "lies inside a git work tree, so it is not changed: put these lines at the top by hand"
                sed 's/^/        /' "$TMPD/block"
            elif [ "$CHECK" = 1 ]; then
                warn "block $state (run without --check)"
            else
                if [ "$state" = absent ]; then
                    { cat "$TMPD/block"; if [ -s "$CLAUDE_FILE" ]; then echo; cat "$CLAUDE_FILE"; fi; } > "$TMPD/claude"
                else
                    replace_region "$CLAUDE_FILE" "$CL_BEGIN" "$CL_END" "$TMPD/block" > "$TMPD/claude"
                fi
                write_file "$CLAUDE_FILE" "$TMPD/claude" "$CL_BEGIN" "$CL_END"
                act "block written to $CLAUDE_FILE; restart Claude Code to pick it up"
            fi ;;
    esac

    if [ -f "$CLAUDE_FILE" ] && grep -qx '# NERSC Agent Guidance' "$CLAUDE_FILE"; then
        pasted_warn
    fi
}

# --- Codex -------------------------------------------------------------------
# stdin: the existing file. stdout: the user's own text: the text below the
# heading, preceded by the text outside the managed part that is not under it
# (above the block, or between block and heading; or, without markers, above the
# heading unless that is a pasted copy of NERSC's file). Without markers or
# heading, the whole file. Blank lines at the edges are dropped.
user_text() {
    awk -v b="$CX_BEGIN" -v e="$CX_END" -v h="$HEADING" -v n="# NERSC Agent Guidance" -v drop="$TMPD/dropped" '
        function emit(from, to,    i, j) {
            while (from <= to && l[from] == "") from++
            while (to >= from && l[to] == "") to--
            if (from > to) return
            if (printed) print ""
            for (i = from; i <= to; i++) print l[i]
            printed = 1
        }
        { l[NR] = $0 }
        END {
            for (i = 1; i <= NR && !bi; i++) if (l[i] == b) bi = i
            for (i = 1; i <= NR && !ei; i++) if (l[i] == e) ei = i
            for (i = (ei ? ei + 1 : 1); i <= NR && !hi; i++) if (l[i] == h) hi = i
            if (bi) {
                emit(1, bi - 1); emit(ei + 1, hi ? hi - 1 : NR)
            } else if (hi) {
                for (i = 1; i < hi && l[i] == ""; i++) ;
                if (l[i] != n) emit(1, hi - 1)
                else for (j = 1; j < hi; j++) print l[j] > drop
            } else {
                emit(1, NR)
            }
            if (hi) emit(hi + 1, NR)
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
    markers_ok "$CODEX_FILE" "$CX_BEGIN" "$CX_END" || return 0
    local managed=0 size
    [ -f "$CODEX_FILE" ] && grep -qxF "$CX_BEGIN" "$CODEX_FILE" && managed=1

    if [ "$UNDO" = 1 ]; then
        if [ "$managed" = 0 ]; then
            ok "no managed part to remove"
        elif in_git_tree "$CODEX_FILE"; then
            warn "lies inside a git work tree, so it is not changed: delete the managed part from"
            more "'$CX_BEGIN' to '$CX_END' by hand"
        else
            replace_region "$CODEX_FILE" "$CX_BEGIN" "$CX_END" "" > "$TMPD/codex"
            write_file "$CODEX_FILE" "$TMPD/codex" "$CX_BEGIN" "$CX_END"
            act "removed the managed part (everything else is kept)"
        fi
        return
    fi

    if [ -f "$CODEX_FILE" ]; then user_text < "$CODEX_FILE" > "$TMPD/user"; else : > "$TMPD/user"; fi
    codex_content "$TMPD/user" > "$TMPD/codex"

    if [ -f "$CODEX_FILE" ] && cmp -s "$TMPD/codex" "$CODEX_FILE"; then
        ok "up to date with NERSC's baseline and the group rules"
    elif in_git_tree "$CODEX_FILE"; then
        warn "lies inside a git work tree, so it is not changed: use a CODEX_HOME outside it"
    elif [ "$CHECK" = 1 ]; then
        if [ "$managed" = 1 ]; then
            warn "stale: perlmutter/agents/ changed (git pull?), or text sits outside the managed part (run without --check)"
        else
            warn "not set up (run without --check)"
        fi
    else
        write_file "$CODEX_FILE" "$TMPD/codex" "$CX_BEGIN" "$CX_END"
        act "managed part written to $CODEX_FILE; restart Codex to pick it up"
        if [ -s "$TMPD/dropped" ] && grep -vxFf "$NERSC_CODEX" "$TMPD/dropped" | grep -q .; then
            more "note: lines not in NERSC's current text are kept only in $BACKUP"
        fi
    fi

    grep -qx '# NERSC Agent Guidance' "$TMPD/user" && pasted_warn
    size=$(wc -c < "$TMPD/codex")
    if [ "$size" -gt "$MAX_BYTES" ]; then
        warn "the file would be $size bytes; Codex reads at most $MAX_BYTES bytes of AGENTS.md text in total"
    fi
}

# --- main --------------------------------------------------------------------
echo "idrobolab-env coding-agent setup"
[ "$CHECK" = 1 ] && echo "(--check: reporting only, nothing will be changed)"
echo
handled=0
if [ -d "$CLAUDE_DIR" ]; then claude; handled=1
else echo "Claude Code: $(tilde "$CLAUDE_DIR") not found, skipped; start Claude Code once and re-run"; fi
echo
if [ -d "$CODEX_DIR" ]; then codex; handled=1
else echo "Codex: $(tilde "$CODEX_DIR") not found, skipped; start Codex once and re-run"; fi
echo
if [ "$handled" = 0 ]; then
    echo "Nothing to do."
elif [ "$PROBLEMS" -eq 0 ]; then
    echo "All good."
else
    echo "$PROBLEMS problem(s) above."
fi
[ "$REFUSED" = 1 ] && exit 1
[ "$CHECK" = 1 ] && [ "$PROBLEMS" -gt 0 ] && exit 1
exit 0
