# 9. ThinLinc and Nion Swift

Graphical programs over plain `ssh -Y` are painfully slow. **ThinLinc** gives you a
remote Linux desktop at NERSC instead; from there, Nion Swift runs on a Perlmutter
compute node with a one-click launcher.

## ThinLinc

**Install the client** from <https://www.cendio.com/thinlinc/download> (Windows,
macOS, Linux).

**Connect** with a fresh `sshproxy` key ([page 1, §3](01-login.md#3-get-todays-key-every-day)):

1. Server: `thinlinc.nersc.gov`. Username: your NERSC username.
2. **Options… → Security → Authentication method: Public key.** Key: your `sshproxy`
   key, `~/.ssh/nersc` (Windows: `C:\Users\<you>\.ssh\nersc`). On Windows, keys made
   in WSL and PuTTY `.ppk` keys don't work; use the `sshproxy` you installed on Windows
   itself.
3. Recommended: **Options… → Advanced → Reconnect policy → "Always ask how multiple
   sessions should be handled"**.
4. On the first connection, compare the host key fingerprint with the ones on
   <https://docs.nersc.gov/connect/> (section "Key Fingerprints").

**What you get:** a desktop that keeps running when you disconnect. Reconnecting puts
you back where you were. Some things to know:

- The ThinLinc machine **is not Perlmutter** and has its **own home directory**. Use
  the **Perlmutter** button or menu entry to open a terminal logged in to Perlmutter.
  A plain terminal on the desktop is on the ThinLinc machine.
- Press **F8** for the ThinLinc menu: full screen, and "grab keyboard" so that
  shortcuts such as Alt+Tab go to the remote desktop instead of your laptop.
- To log in to Perlmutter from a ThinLinc terminal without a password (the Nion Swift
  launcher needs this), run `sshproxy -u <username>` **in a ThinLinc terminal**. That
  key, too, lasts 24 hours.

## Nion Swift

Nion Swift is installed once for the whole group, so there is nothing to install. The
install, at `/global/common/software/<project>/venvs/nionswift-py313`, contains nionswift,
nionswift-tool, nionswift-usim, nionswift-eels-analysis and nionswift-experimental.

### One-time launcher setup

In a **ThinLinc terminal** (not the Perlmutter one):

```bash
sshproxy -u <username>        # if you haven't today in this ThinLinc session
scp perlmutter.nersc.gov:idrobolab-env/perlmutter/helpers/setup-nionswift-launcher.sh ~
bash ~/setup-nionswift-launcher.sh
```

This first `scp` may ask for password+OTP; the setup script then configures the
key. It adds **Nion Swift (Perlmutter)** to the menu and an icon to the desktop. MATE may
ask you to trust the icon on its first click.

### Starting Nion Swift

Click the icon. A terminal asks for the **memory** in GB (default 64) and the
**wall time** in hours (default 4, also the maximum). Up to 256 GB it books a slice of
a CPU node (`shared_interactive`, charged for the slice). Above that, it books a whole
node. Once the job starts, Nion Swift opens.

- Closing Nion Swift ends the job, and with it the charge. Closing the terminal while
  the job is still waiting cancels it.
- The allocation is charged while Swift sits idle, so close it when you're done.
- Put the Swift library and working data on `$SCRATCH` for speed. Keep the master
  copies of your raw data on CFS ([page 3](03-storage-and-transfer.md)).

**Without the launcher**, from the Perlmutter terminal in ThinLinc:

```bash
salloc -C cpu -q shared_interactive -A <project> -t 4:00:00 -n 1 -c 32
hostname               # must print nid..., not login...
echo $DISPLAY          # must not be empty
/global/common/software/<project>/venvs/nionswift-py313/bin/nionswift
```

If `$DISPLAY` is empty, keep the allocation and open a second Perlmutter terminal.
Run `squeue --me` there to find the node name (`nid...`), then `ssh -Y <node>` and
start Swift in that shell.

### Your own Nion Swift install

You only need this for extra plugins or a different version. On a Perlmutter login
node:

```bash
uv venv --python 3.13 ~/venvs/nionswift
uv pip install -p ~/venvs/nionswift nionswift nionswift-tool nionswift-usim \
    nionswift-eels-analysis nionswift-experimental      # + any plugins
~/venvs/nionswift/bin/nionswift                           # inside an allocation, as above
```

- Use **Python 3.13**: Nion's UI crashes on 3.14.
- Use a **uv-managed** Python as above, not a conda or `module load python` one. With
  those, Swift quits silently with no window
  ([nionswift#1946](https://github.com/nion-software/nionswift/issues/1946)).

### If something goes wrong

| Symptom | Fix |
|---|---|
| Launcher asks for a password or fails at once | the ThinLinc-side key expired: `sshproxy -u <username>` in a ThinLinc terminal |
| Window blank, black or crashing | before starting Swift: `export QT_XCB_GL_INTEGRATION=none QT_OPENGL=software LIBGL_ALWAYS_SOFTWARE=1` |
| `salloc` refused | the interactive wall-time limit is 4 h. Longer sessions: see the reference doc |
| Swift exits silently, no window | wrong Python (see above) |

Reference, with the maintainer setup and the full troubleshooting chain:
[`reference/nionswift-perlmutter-thinlinc.md`](reference/nionswift-perlmutter-thinlinc.md).
