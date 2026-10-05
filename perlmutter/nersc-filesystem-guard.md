# NERSC's filesystem-guard hook for AI agents

On Perlmutter login nodes, NERSC checks every shell command an AI coding agent runs
before the agent runs it. The hook stops accidental scans of the shared filesystems
(`find /`, `du` over all of scratch, and so on). It also blocks some harmless recursive
`grep` commands. This page describes what the hook checks, what it blocks, and how to
write the commands it blocks by mistake.

Checked on 2026-10-05 (UTC) against the hook file dated 2026-08-19, sha256
`db3583bedec4fd05b9fe9d50842e340d830f7f27d334030bc570edec8ffd6040`. NERSC can change
the hook at any time. If its behaviour no longer matches this page, compare the checksum.

## Where it is installed

| | |
|---|---|
| Hook script | `/global/common/software/nersc/agents/hooks/nersc_filesystem_guard.py` (the only file under `/global/common/software/nersc/agents/`) |
| Registered by | `/etc/claude-code/managed-settings.json`: system-wide, root-owned, and above all user and project settings |
| Event | Claude Code `PreToolUse`, matcher `Bash`; runs `/usr/bin/python3` (3.6.15) with a 2 s timeout and status line "Checking filesystem traversal scope" |
| Output | Prints a `permissionDecision: "deny"` JSON object when it blocks; prints nothing when it allows |

Its docstring says "before Codex executes them", so NERSC presumably uses the same script
for Codex. It is described as "a guardrail against accidental agent behavior, not a
security boundary".

Only the agent's **Bash tool** is checked. Claude Code's own Read, Grep and Glob tools
do not pass through it, and neither do commands typed by a person.

## What it checks

For each command in a pipeline or `;`/`&&` chain, the hook first strips variable
assignments and the wrappers `env`, `sudo`, `nice`, `timeout`, `nohup`, `time`,
`command` and `exec`. It then checks these commands:

| Command | When it is checked | What it treats as the directory being scanned |
|---|---|---|
| `find`, `bfs` | always | the paths before the first expression (default `.`) |
| `du`, `fd`, `fdfind`, `tree` | always | every argument not starting with `-` (default `.`) |
| `rg` | only with `--files` | every argument not starting with `-` (default `.`) |
| `grep` | only with `-r`/`-R` | every argument not starting with `-`, **including the pattern** |
| `ls` | only with `-R` | every argument not starting with `-` (default `.`) |
| `python…`, `pypy…` | when the code calls `os.walk`, `.rglob` or `glob.glob` | any quoted absolute path in the code |

It also checks the command inside `bash -c` / `sh -c` (up to 3 levels deep),
`sbatch --wrap` and `srun … <command>`.

Each such directory is expanded (`~` and `$VAR`, using the hook's own environment),
cut off at the first glob character (`*?[{`), made absolute against the session's
working directory, and resolved with `realpath`. The command is **blocked** if:

1. the resolved directory is one of the broad roots: `/`, `/global`, `/global/cfs`,
   `/global/cfs/cdirs`, `/global/cfs/projectdirs`, `/global/common`,
   `/global/common/software`, `/global/homes`, `/global/u1`, `/global/u2`, `/opt`,
   `/pscratch`, `/pscratch/sd`, `/usr`, `/usr/common`, `/usr/local`, `/cvmfs`, and
   `/dvs_ro/…`, `/dvs_rw/…` (`common`, `u1`, `u2`, `dna`, `cfs`);
2. the resolved directory is a one-letter bucket: `/global/{homes,u1,u2}/<x>` or
   `/pscratch/sd/<x>`;
3. the directory cannot be worked out, such as `$(...)`, backticks, or an unset
   `$VAR`;
4. the command follows symlinks: `find -H/-L/-follow`, `du -D/-H/-L`, `fd -L`,
   `tree -l`, `rg -L`, `grep -R`, `ls -R` with `-H`/`-L`.

Anything below those roots is allowed: your home directory, `$PSCRATCH/<dir>`, a named
CFS project directory, and `/global/common/software/<project>`. Options that limit the
search, such as `-maxdepth` or `-name`, are ignored. **`find / -maxdepth 1` is still
blocked.**

## Harmless commands it blocks

With `grep -r`, the hook treats the search pattern as a directory too, so many ordinary
regular expressions get the command blocked. These results were measured by feeding the
hook test commands (cwd = home directory). Each row is one command; the right-hand
column is the hook's decision:

| Command | Decision |
|---|---|
| `grep -rn 'def foo' src/` | allowed |
| `grep -rn 'foo$' src/` | blocked: "cannot determine traversal root 'foo$'" (the `$`) |
| `grep -rnE '[a-z]+_x' src/` | blocked: "resolves to broad shared root '/'" (the `[` cuts the pattern down to `/`) |
| `grep -rn -e 'foo$' src/` | blocked (a separate `-e` does not help) |
| `grep -rn --regexp='foo$' src/` | allowed |
| `rg -n 'foo$' src/` | allowed |
| `find "$(pwd)" -name x` | blocked: "cannot determine traversal root" |
| `find $PSCRATCH/abtem-git -name '*.py'` | allowed (the `$VAR` expands) |

To search a bounded tree with a regex containing `$`, `[`, `*`, `?` or `{`, attach the
pattern to the option with `--regexp='…'`, or use `rg` without `--files`. Write a
directory as a literal path or `$VAR`, not as `$(...)`.

## Broad scans it does not catch

It recognises only the command names listed above, and it does not follow `cd`. In the
same test, these went through although they scan broad roots: `rg -l pattern
/global/common` (`rg` is only checked with `--files`), `cd / && find .`,
`echo / | xargs find`, `uv run python -c "…os.walk('/')"` (the `uv` launcher is not
looked through), `locate`, and commands inside `podman-hpc run`.

The hook does not make a scan acceptable. These gaps are listed so nobody mistakes "not
blocked" for "fine". A blocked command is narrowed to a bounded directory, never
rewritten to get past the hook.

## Software discovery

The hook's own message suggests `command -v <tool>`, `type -a <tool>` or
`module spider <name>` instead of searching the software trees.
