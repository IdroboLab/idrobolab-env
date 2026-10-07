# 9. ThinLinc and Nion Swift

Graphical programs over plain `ssh -Y` are painfully slow. **ThinLinc** gives you a
remote Linux desktop at NERSC instead; from there, Nion Swift runs on a Perlmutter
compute node with a one-click launcher.

## ThinLinc

### Install the client

Download the client from <https://www.cendio.com/thinlinc/download>. Cendio's
installation instructions for each system:
[Windows](https://www.cendio.com/resources/docs/tag/client_windows.html),
[macOS](https://www.cendio.com/resources/docs/tag/client_macos.html),
[Linux](https://www.cendio.com/resources/docs/tag/client_linux.html).

#### Windows

Download `tl-<version>-client-windows.exe` (x64), run it and follow the instructions.
The client is added to the Start menu: start it from there.

#### macOS

Download `tl-<version>-client-macos.dmg`, double-click it, drag the ThinLinc client
application to Applications (or another folder), and eject the volume. Start it by
double-clicking the application.

#### Linux

Download the package for your distribution (`amd64` / `x86_64` or `arm64` / `aarch64`)
and install it:

```bash
sudo dpkg -i thinlinc-client_<version>_amd64.deb        # Debian, Ubuntu
sudo rpm -Uvh thinlinc-client-<version>.x86_64.rpm      # Fedora, Red Hat, SUSE
```

Start it from the ThinLinc client icon of your desktop menu (usually in the Internet
category) or with `/opt/thinlinc/bin/tlclient`.

### Connect

Connect with a fresh `sshproxy` key ([page 1, §3](01-login.md#3-get-todays-key-every-day)):

1. Server: `thinlinc.nersc.gov`. Username: your NERSC username.
2. **Options… → Security → Authentication method: Public key.** Key: your `sshproxy`
   key `nersc` in the `.ssh` folder of your home folder: `C:\Users\<you>\.ssh\nersc` on
   Windows, `/Users/<you>/.ssh/nersc` on macOS, `/home/<you>/.ssh/nersc` on Linux. On
   Windows, keys made in WSL and PuTTY `.ppk` keys don't work; use the `sshproxy` you
   installed on Windows itself.
3. Recommended: **Options… → Advanced → Reconnect policy → "Always ask how multiple
   sessions should be handled"**.
4. On the first connection, compare the host key fingerprint with the ones on
   <https://docs.nersc.gov/connect/> (section "Key Fingerprints").

**What you get:** a desktop that keeps running when you disconnect. Reconnecting puts
you back where you were. Some things to know:

- The ThinLinc machine **is not Perlmutter** and has its **own home directory**. Use
  the **Perlmutter** button or menu entry to open a terminal logged in to Perlmutter.
  A terminal opened any other way runs on the ThinLinc machine.
- **The ThinLinc home is separate from your Perlmutter home**, although `$HOME` prints
  the same path on both: files you create on one do not appear on the other. The
  ThinLinc home survives logouts, so `~/.ssh` and your menu entries stay. The
  exception is `~/Desktop`: when you start a new session after a complete logout, it
  is emptied and only NERSC's own icons come back. Reconnecting to a session that is
  still running does not reset it. (This was observed on 2026-10-07; NERSC does not
  document it.) The setup below installs an autostart entry that puts our shortcuts
  back at every session start, and the same launchers are in the applications menu, so
  they are never lost.
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

The first time, you have no terminal icon yet. Open a terminal on the ThinLinc
machine through the run dialog: press `Alt+F2` (if your own computer grabs it, press
`F8` first and choose *Grab keyboard*), tick **Run in terminal** on MATE, and run
`bash` (this route has not been tested on NERSC's ThinLinc desktop yet;
[details](reference/nionswift-perlmutter-thinlinc.md#53-launching-from-the-keyboard-inside-thinlinc)).
Once the setup has run, use the **Terminal (ThinLinc host)** icon for every step on
this page that says "in a ThinLinc terminal", such as `sshproxy -u <username>`.

In a **ThinLinc terminal** (not the Perlmutter one):

```bash
sshproxy -u <username>        # if you haven't today in this ThinLinc session
scp perlmutter.nersc.gov:idrobolab-env/perlmutter/helpers/setup-nionswift-launcher.sh ~
bash ~/setup-nionswift-launcher.sh
```

This first `scp` may ask for password+OTP; the setup script then configures the
key. It adds **Nion Swift (Perlmutter)** to the menu and an icon to the desktop, plus
a second icon and menu entry, **Terminal (ThinLinc host)**, which opens a terminal on
the ThinLinc machine (not on Perlmutter), and the autostart entry mentioned above.
MATE may ask you to trust the icons on their first click. Run the script again
whenever you want to repair or update these; it overwrites its own files and
duplicates nothing.

### Starting Nion Swift

Click the icon on the desktop (or choose it in the applications menu). A terminal asks
for the **memory** in GB (default 64) and the **wall time** in hours (default 4, also
the maximum). Up to 256 GB it books a slice of a CPU node (`shared_interactive`,
charged for the slice). Above that, it books a whole node. Once the job starts, Nion
Swift opens.

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
