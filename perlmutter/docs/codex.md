# Codex on Perlmutter

A step-by-step guide to OpenAI's Codex CLI on a Perlmutter login node. The rules on the
[coding-agents page](10-coding-agents.md#rules) apply to Codex as to any agent; NERSC's
own page is <https://docs.nersc.gov/development/coding-agents/codex/>.

## 1. Install

You need a ChatGPT account (the free plan includes limited use). On a login node, from
`$HOME`:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version
```

If `codex` is not found, the installer's last lines say which directory it installed
into; add that directory to `PATH` in `~/.bashrc`.

## 2. Log in

Perlmutter has no browser, so use one of these:

- **Device code (simplest).** First allow device-code login for Codex once, in the
  security settings of your ChatGPT account on your laptop. Then, on Perlmutter:
  ```bash
  codex login --device-auth
  ```
  Open the printed link on your laptop, sign in and enter the one-time code.
- **Port forwarding.** Connect with the login callback port forwarded, then log in and
  open the printed URL in your laptop's browser:
  ```bash
  ssh -L 1455:localhost:1455 perlmutter
  codex login
  ```

The login is stored in `~/.codex/auth.json`. Treat that file like a password: never
copy it into a project, a shared folder or git.

## 3. Settings

Codex reads `~/.codex/config.toml`. NERSC recommends:

```bash
mkdir -p ~/.codex && chmod go-rwx ~/.codex
cat >> ~/.codex/config.toml <<'EOF'
sandbox_mode = "workspace-write"
approval_policy = "on-request"
EOF
```

- **`workspace-write`**: Codex may edit files in the folder you started it in without
  asking, and nothing outside it.
- **`on-request`**: anything outside that sandbox needs your approval first. That
  includes commands that use the network, so expect a prompt for `git pull`/`push`,
  `uv` installs and probably `sbatch`/`squeue`. Read each one before approving.

Don't use `danger-full-access` or a flag that skips approvals.

## 4. Instructions: NERSC's baseline, the group's and the project's

Codex reads instruction files called `AGENTS.md` and puts them all into its context:

| File | What goes there |
|---|---|
| `~/.codex/AGENTS.md` | your personal file: NERSC's baseline and the group's rules (managed by a script), then your own preferences |
| `AGENTS.md` at the top of a git repository, and in subfolders down to where you start Codex | project rules; files closer to your folder come later and so take precedence |

Set up the personal file with the group's script, from your clone of `idrobolab-env`
and after your first login (which creates `~/.codex`):

```bash
~/idrobolab-env/perlmutter/helpers/setup-agents.sh
```

Your own preferences always go **below the `## Local additions` heading**. Codex cannot
import files, so run the script again after each `git pull` of `~/idrobolab-env`.
[Page 10](10-coding-agents.md#instructions-three-layers) describes what it does, for
both agents.

For a project, put an `AGENTS.md` in the repository root: what the project is, how to
run its tests, which data it must not touch. Inside a session, `/init` drafts one. Keep
all of them short: Codex reads at most 32 KiB of `AGENTS.md` text in total, and the
script warns when the personal file alone is over that.
`idrobolab-env` has one already ([AGENTS.md](../../AGENTS.md)).

## 5. Use it

```bash
cd ~/my-project
codex                                   # interactive session in this folder
codex exec "summarise what run.py does"  # one task, prints the result and exits
```

- Start Codex in the project folder, not in `$HOME`: the sandbox is the folder you
  start in.
- Let it prepare job scripts, and submit them yourself or approve each submission
  with the account, QOS, GPU count and time limit in view ([page 4](04-jobs.md)).
- Review its changes with `git diff` before you commit them.

Codex also comes as a desktop app and an editor extension that can connect to
Perlmutter over SSH; NERSC's page describes that setup.
