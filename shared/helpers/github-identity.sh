# github-identity.sh: the git e-mail address for GitHub repositories.
# Sourced by the setup-user.sh scripts, not run. The caller defines ok, warn
# and act. idrobolab-env and ruszlab-env each carry this file; keep the two
# copies identical.
#
# Commits in a repository with a github.com remote take user.email from
# ~/.gitconfig-github, which three includeIf entries in the global git config
# pull in (git 2.36 or newer). Every other repository keeps the global
# user.email. A GitHub noreply address (<id>+<user>@users.noreply.github.com,
# shown under GitHub > Settings > Emails) keeps the personal address out of
# public commits and still counts them as contributions.

GITHUB_IDENTITY_FILE="$HOME/.gitconfig-github"
GITHUB_IDENTITY_PATH='~/.gitconfig-github'   # as written into the global config
GITHUB_IDENTITY_KEYS=(
    'includeIf.hasconfig:remote.*.url:https://github.com/**.path'
    'includeIf.hasconfig:remote.*.url:git@github.com:*/**.path'
    'includeIf.hasconfig:remote.*.url:ssh://git@github.com/**.path'
)

# True for one address: something@host.tld, no whitespace.
github_identity_valid() {   # ADDRESS
    case "$1" in
        *[[:space:]]*|*@*@*) return 1 ;;
        ?*@?*.?*) return 0 ;;
        *) return 1 ;;
    esac
}

github_identity_set() {   # ADDRESS
    local key
    git config -f "$GITHUB_IDENTITY_FILE" user.email "$1"
    for key in "${GITHUB_IDENTITY_KEYS[@]}"; do
        git config --global "$key" "$GITHUB_IDENTITY_PATH"
    done
}

# git, outside any repository the calling environment may name.
github_identity_git() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR git "$@"
}

# The address a commit in a repository with a github.com remote would carry:
# asked of git itself, in a throwaway repository, once for each of the three
# remote forms, so that an old git, a later user.email in the global config or
# a half-written rule all show. Prints the address, or a line starting with
# "differs:" when the three forms do not give the same one.
github_identity_effective() {
    local dir url addrs=()
    dir=$(mktemp -d 2>/dev/null) || { git config --global --get user.email 2>/dev/null || true; return 0; }
    if github_identity_git -C "$dir" init -q --template= 2>/dev/null; then
        for url in https://github.com/o/r git@github.com:o/r.git ssh://git@github.com/o/r.git; do
            github_identity_git -C "$dir" config remote.origin.url "$url" 2>/dev/null || true
            addrs+=("$(github_identity_git -C "$dir" config --get user.email 2>/dev/null || true)")
        done
    else
        addrs=("" "" "")
    fi
    rm -rf "$dir"
    if [ "${addrs[0]}" = "${addrs[1]}" ] && [ "${addrs[1]}" = "${addrs[2]}" ]; then
        echo "${addrs[0]}"
    else
        echo "differs: ${addrs[0]:-none} for https://github.com/, ${addrs[1]:-none} for git@github.com:, ${addrs[2]:-none} for ssh://git@github.com/"
    fi
}

# The overview: which address commits in GitHub repositories carry, with a
# warning when it is not a GitHub noreply address or not the one the rule names.
github_identity_report() {
    local addr rule=""
    addr=$(github_identity_effective)
    case "$addr" in
        "differs: "*)
            warn "commits in GitHub repositories carry an address that depends on the form of the remote (${addr#differs: }): the rule is incomplete, run setup-user.sh --github-email ADDRESS"
            return 0 ;;
    esac
    if [ -f "$GITHUB_IDENTITY_FILE" ]; then
        rule=$(git config -f "$GITHUB_IDENTITY_FILE" --get user.email 2>/dev/null || true)
    fi
    if [ -n "$rule" ] && [ "$rule" != "$addr" ]; then
        warn "$GITHUB_IDENTITY_PATH names $rule, but commits in GitHub repositories carry ${addr:-no address}: the rule needs git 2.36 ($(git --version 2>/dev/null)), all three includeIf entries (--github-email writes them) and no user.email set after them in the global git config"
        return 0
    fi
    case "$addr" in
        "") ok "git has no e-mail address for GitHub repositories (setup-user.sh --github-email ADDRESS sets one)" ;;
        *@users.noreply.github.com) ok "commits in GitHub repositories carry $addr" ;;
        *) warn "commits in GitHub repositories carry $addr, not a GitHub noreply address: run setup-user.sh --github-email <id>+<user>@users.noreply.github.com" ;;
    esac
}

# Removes the three entries, whether they name the file with a tilde or by its
# full path; ~/.gitconfig-github stays.
github_identity_undo() {
    local key value removed=0
    for key in "${GITHUB_IDENTITY_KEYS[@]}"; do
        value=$(git config --global --get "$key" 2>/dev/null || true)
        if [ "$value" = "$GITHUB_IDENTITY_PATH" ] || [ "$value" = "$GITHUB_IDENTITY_FILE" ]; then
            git config --global --unset "$key"
            removed=1
        fi
    done
    if [ "$removed" = 1 ]; then
        echo ">> removed the GitHub e-mail rule from the global git config ($GITHUB_IDENTITY_PATH is kept)"
    fi
}
