#!/bin/bash
# check-setup.sh — check your Perlmutter setup for idrobolab-env and report.
# Run it on a login node from your own clone, after the one-time setup, after a
# `git pull`, or after moving your clone:
#
#     ~/idrobolab-env/perlmutter/helpers/check-setup.sh
#
# It changes no file outside the clone's .git directory, where its fetch
# updates git's record of GitHub. It never prompts. It prints OK / NOTE /
# FAIL lines in three sections:
#   1. this clone: remote, branch, commits behind or ahead of GitHub,
#      uncommitted changes;
#   2. the shell: the output of `setup-user.sh --check` (which includes
#      `setup-agents.sh --check` once you have run that), whether env.sh is
#      active in this shell, and whether $IDROBOLAB_IMAGE is the name this
#      clone's env.sh gives (an older name stays exported until you log in
#      again after a pull);
#   3. leftovers: paths to another idrobolab-env or hpcenvs clone, or to the
#      retired shared checkout /global/cfs/cdirs/<project>/env, in your shell
#      startup files, git and ssh config, crontab and scrontab, ~/bin,
#      ~/.local/bin, your Jupyter kernels and your agents' instruction files;
#      links up to three levels below $HOME that point there or nowhere.
# Exits 1 when it printed a FAIL line.
set -uo pipefail

case "${1:-}" in
    "") ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
esac

HELPERS=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CLONE=$(dirname "$(dirname "$HELPERS")")
CLONE_REAL=$(readlink -f "$CLONE")
PROJECT=${NERSC_PROJECT:?export NERSC_PROJECT=<project> (setup-user.sh writes it into your shell profile)}

fails=0
ok()   { printf 'OK    %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
note() { printf 'NOTE  %s\n' "$*"; }
indent() { sed 's/^/      /'; }

echo "== 1. this clone: $CLONE"
if git -C "$CLONE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$CLONE" branch --show-current)
    ok "remote $(git -C "$CLONE" remote get-url origin 2>/dev/null || echo '(none)'), branch ${branch:-(detached)}"
    [ "$branch" = main ] || note "your shell reads env.sh from this checkout, so it runs branch '${branch:-(detached)}', not main"
    # No password or passphrase prompt over HTTPS or ssh, and no askpass dialog;
    # keep the user's own ssh command (a custom key) and add BatchMode to it.
    ssh_cmd=${GIT_SSH_COMMAND:-$(git -C "$CLONE" config core.sshCommand || echo ssh)}
    if GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GIT_SSH_COMMAND="$ssh_cmd -o BatchMode=yes" \
           timeout 60 git -C "$CLONE" fetch -q origin 2>/dev/null; then
        since="GitHub"
    else
        since="the last successful fetch"
        note "fetch failed (no network, or no key or credentials loaded?): compared with $since"
    fi
    if counts=$(git -C "$CLONE" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null); then
        read -r behind ahead <<<"$counts"
        if [ "$behind" -gt 0 ]; then note "$behind commit(s) behind $since: git -C $CLONE pull"
        else ok "up to date with $since"; fi
        [ "$ahead" -gt 0 ] && note "$ahead local commit(s) not on GitHub"
    else
        note "branch has no upstream to compare with"
    fi
    changes=$(git --no-optional-locks -C "$CLONE" status --porcelain)
    if [ -n "$changes" ]; then note "uncommitted changes:"; indent <<<"$changes"
    else ok "no uncommitted changes"; fi
else
    bad "$CLONE is not a git clone"
fi

echo "== 2. shell"
out=$("$HELPERS/setup-user.sh" --check 2>&1)
indent <<<"$out"
grep -q 'warning(s) above' <<<"$out" && note "setup-user.sh --check printed warnings (above)"
if [ -z "${IDROBOLAB_IMAGE:-}" ]; then
    bad "env.sh is not active in this shell (IDROBOLAB_IMAGE unset): see the shell startup check above, then log in again"
else
    want=$(env -u IDROBOLAB_IMAGE bash --noprofile --norc -c \
        '. "$1" >/dev/null 2>&1; printf %s "${IDROBOLAB_IMAGE:-}"' _ "$CLONE/perlmutter/env.sh")
    if [ "$IDROBOLAB_IMAGE" = "$want" ]; then
        ok "IDROBOLAB_IMAGE=$IDROBOLAB_IMAGE"
    else
        note "IDROBOLAB_IMAGE=$IDROBOLAB_IMAGE, but this clone's env.sh gives ${want:-nothing}: log in again, unless you set it yourself"
    fi
fi

echo "== 3. leftovers from another clone or the old shared checkout"
# A path names another clone when the part up to its idrobolab-env* directory
# (idrobolab-env, idrobolab-env.old, ...) does not resolve to this clone. Every
# hpcenvs* path is a leftover, since that repo is frozen. URLs and remote paths
# (https://..., git@host:..., host:/... at the start of a word) are removed
# first. grep picks the candidate lines, so a file costs one process.
# Sets REPO_NAME (idrobolab-env or hpcenvs) and REPO_DIR when path $1 names one:
# the exact directory name, or a renamed copy (idrobolab-env.old, ...) when more
# path follows it or it is a directory, so a file merely named like the repo is
# not taken for a clone.
names_repo() {
    [[ $1 =~ ^(.*/(idrobolab-env|hpcenvs)([^/]*))(/|$) ]] || return 1
    REPO_NAME=${BASH_REMATCH[2]} REPO_DIR=${BASH_REMATCH[1]}
    [ -z "${BASH_REMATCH[3]}" ] || [ -n "${BASH_REMATCH[4]}" ] || [ -d "$REPO_DIR" ]
}
scan() {  # $1: where the text came from; text on stdin
    local where=$1 n line tok p
    local retired="(cdirs|projectdirs)/$PROJECT/env([/\"';:)[:space:]]|\$)"
    while IFS=: read -r n line; do
        if [[ $line =~ $retired ]]; then
            bad "$where:$n: names the retired shared checkout: $line"
        fi
        while IFS= read -r tok; do
            [ -n "$tok" ] || continue
            p=${tok/#\~/$HOME}; p=${p/#\$\{HOME\}/$HOME}; p=${p/#\$HOME/$HOME}
            names_repo "$p" || continue
            if [ "$REPO_NAME" = hpcenvs ]; then
                bad "$where:$n: names an hpcenvs clone: $tok"
            elif [ "$(readlink -m "$REPO_DIR")" != "$CLONE_REAL" ]; then
                bad "$where:$n: names $tok, not this clone"
            fi
        done < <(sed -E "s#[a-z+]+://[^[:space:]\"']*##g; s#[[:alnum:]._-]+@[[:alnum:].-]+:[^[:space:]\"']*##g; s#(^|[[:space:]])[[:alnum:]._-]+:[/~][^[:space:]\"']*#\\1#g" <<<"$line" |
                 grep -oE "(~|\\\$\{?HOME\}?|/)[^[:space:]\"';:()]*")
    done < <(grep -nE "idrobolab-env|hpcenvs|dirs/$PROJECT/env")
}
for f in ~/.bashrc ~/.bash_profile ~/.profile ~/.bashrc.ext ~/.bash_profile.ext \
         ~/.gitconfig ~/.config/git/config ~/.ssh/config \
         "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md" "${CODEX_HOME:-$HOME/.codex}/AGENTS.md" \
         ~/bin/* ~/.local/bin/* ~/.local/share/jupyter/kernels/*/kernel.json; do
    [ -f "$f" ] && grep -qI . "$f" 2>/dev/null && scan "$f" < "$f"
done
scan crontab < <(crontab -l 2>/dev/null)
command -v scrontab >/dev/null 2>&1 && scan scrontab < <(scrontab -l 2>/dev/null)
while IFS= read -r -d '' l; do
    t=$(readlink -m "$l")
    case "$t" in
        "$CLONE_REAL"|"$CLONE_REAL"/*) ;;
        *) if names_repo "$t"; then bad "link $l -> $(readlink "$l"), not into this clone"
           elif [ ! -e "$l" ]; then note "dangling link $l -> $(readlink "$l")"; fi ;;
    esac
done < <(find -H "$HOME" -maxdepth 3 \( -path "$HOME/.cache" -o -path "$CLONE" \) -prune -o -type l -print0 2>/dev/null)

echo
if [ "$fails" -eq 0 ]; then echo "No FAIL lines."; else echo "$fails FAIL line(s) above."; exit 1; fi
