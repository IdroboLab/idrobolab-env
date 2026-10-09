# 3. Globus: moving data between machines

Globus is a free service for copying large amounts of data between two places, such as a
supercomputing centre, your university's storage, and the PC of a microscope. You tell it
what to copy through a web page; it does the copying in the background and tells you when
it is done. This page is a tour of the web app for someone who has never used it. What is
specific to NERSC (the collections, the paths, sharing from our project directory) is in
[Perlmutter page 3](perlmutter/03-storage-and-transfer.md#globus-large-data-many-files-or-unattended).
Globus's own tutorials are at <https://docs.globus.org/guides/tutorials/>.

## 1. What Globus is, and when to use it

Globus describes its transfers as "fire-and-forget": it manages the transfer, retries after
network errors, and by default **verifies file integrity with checksums** after the copy
([File Transfer tutorial](https://docs.globus.org/guides/tutorials/manage-files/transfer-files/)).
The data flows between the two storage systems, so you can close the browser. If one end
is a laptop or instrument PC (section 6), the transfer is suspended while that machine is
off or offline and resumes when it is back, unless three or more days have passed.
Globus is free for researchers at non-profit institutions
([subscriptions FAQ](https://docs.globus.org/faq/subscriptions/)).

| | `rsync` / `scp` | Globus |
|---|---|---|
| Good for | a few files or folders, up to about 10 GB; anything you want to script quickly | many files, hundreds of GB and more, transfers that should run unattended |
| Needs | ssh access to the machine | a *collection* (section 3) on both sides, and a Globus login |
| If the connection drops | the command stops; re-run it | Globus retries and finishes by itself (a laptop end pauses until the laptop is back) |
| Checks the copy | compares size and time; `--checksum` compares content | by default, with checksums |

Use rsync for the small everyday copy and Globus for the big or unattended one. Globus is
not a backup, and it cannot reach a machine that has no collection.

## 2. Log in

1. Open <https://app.globus.org> and click **Log In**.
2. Choose your **organisation** (your university) from the list and sign in with the
   usual university account. Globus can also create an account from Google, ORCID or
   GitHub, or from a Globus ID of its own; if you already have an account, use the same
   organisation every time, so that you land in the same Globus account.
3. The first time, Globus asks whether to link an existing account and asks you to consent
   to its use of your identity ("to access information and perform actions (including file
   transfers) on your behalf"). Consent.

Your Globus account can hold several **identities**: your university login, and for
example a NERSC login later on. To link one, open the **Identities** page and click
**Link Another Identity**, choose the organisation (here: NERSC) from the drop-down, and
authenticate with it as you normally would; Globus then asks you to authenticate with your
primary identity to complete the linking
([how to link](https://docs.globus.org/guides/tutorials/manage-identities/link-to-existing/)).
Linked identities are shown on the same page. If you have no NERSC account yet, come back to
this paragraph after [Perlmutter page 1](perlmutter/01-login.md). Whether a collection
needs the link depends on the collection; the NERSC specifics are in
[Perlmutter page 3](perlmutter/03-storage-and-transfer.md#globus-large-data-many-files-or-unattended).

Globus sends its notifications to the e-mail address of your identity, so check that it is
one you read.

## 3. Collections

A **collection** is "a named location containing data you can access with Globus": a folder
tree on a particular storage system. Everything you copy goes from one collection to another,
and you always pick them by name. Globus
([overview](https://docs.globus.org/guides/overviews/collections-and-endpoints/)) knows two
kinds:

- A **mapped collection** is a point of access to a storage system that "uses the
  credentials of the currently logged-in user". It is run by the site (a university, a
  supercomputing centre) and you open it with your account at that site; you see what that
  account sees. NERSC's collections are of this kind.
- A **guest collection** is a folder on a mapped collection, made by someone who owns that
  folder, and made accessible to other people with permissions of their choosing
  ([section 7](#7-sharing-data-with-someone)). The people it is shared with need no account
  at the site.

Your laptop or an instrument PC becomes a collection when **Globus Connect Personal**
runs on it ([section 6](#6-globus-connect-personal)).

## 4. The File Manager

Click **File Manager** in the menu on the left. (The other entry you need is
**Activity**, section 5; the rest of the menu belongs to other Globus services.)

1. **Find a collection.** Click the **Collection** field at the top and start typing a
   name, such as the name of your university's storage or "NERSC DTN". Globus lists the
   collections with matching names; click one. A collection that belongs to a site may ask
   you to sign in with that site's account first.
2. **Look around.** The panel shows the folders and files of the collection. The **Path**
   field is editable: click it, type a path such as `/home/share/godata/` and press Enter.
   Click a folder name to go into it.
3. **Open the second panel.** Click **Transfer or Sync to...** in the panel on the right of
   the page. A second panel opens; choose the other collection and path there the same
   way. The two panels are the two ends of a transfer.
4. **Bookmarks.** A *bookmark* saves a collection and path you open often under a name
   you choose ([bookmarks](https://docs.globus.org/api/transfer/collection_bookmarks/));
   look for the bookmark icon beside the collection and path.
5. **Select what to copy.** Select each file or folder you want in the *source* panel.
   A folder is copied with everything in it.

## 5. Start a transfer and follow it

Before you start, open the **Transfer & Timer Options** drop-down. By default, Globus
"verifies file integrity after transfer using checksums", and the information icon next to
each option explains it; the wording of the options in the app changes now and then, so
read it there. The ones you will use (the second column names the setting in the Globus command line,
[reference](https://docs.globus.org/cli/reference/transfer/)):

| Option, in the app | Setting | What it does |
|---|---|---|
| **sync** | `--sync-level` (`exists`, `size`, `mtime`, `checksum`) | Copies only what is new or changed, by the rule you pick, instead of everything. Use it to repeat or resume a copy |
| **verify file integrity after transfer** | `--verify-checksum` (default) | Compares checksums of the copy and the original |
| **encrypt transfer** | `--encrypt` | Encrypts the file data in transit (TLS) |
| **delete files on destination** that do not exist on the source | `--delete-destination-extra` | Makes the destination folder an exact mirror of the source and **deletes** extra files there. Leave it off unless you mean it |
| a **label** | `--label` | A name for the transfer in the Activity list. Use one |
| e-mail notification | `--notify` | When the transfer succeeds, fails or needs attention |

Then click **Start** (the button above the source panel; there is one for each direction).
A green notice confirms that Globus accepted the request, and the transfer runs in the
background.

**Activity** (in the menu on the left) lists your transfers with their status.
Click the arrow icon on the right of a transfer for its details: the **Overview** tab shows
what was transferred and has the **Cancel Task** button, and the **Event Log** tab shows
what happened, including permission errors, retries and pauses. A transfer that reports
"permission denied" usually points to a folder or file the account at the other end may
not read. When it is done, Globus e-mails you; the summary of a task is kept for 90 days
and its details for 30 days. A user can have 3 active and 100 pending transfers; further
ones wait in the queue ([FAQ](https://docs.globus.org/faq/transfer-sharing/)).

To restart a transfer that failed in part, submit it again with **sync** at the checksum
level (on the command line, `--sync-level checksum`): it copies only the files that are
missing or differ
([FAQ](https://docs.globus.org/faq/transfer-sharing/)).

## 6. Globus Connect Personal

**Globus Connect Personal** (GCP) is a small program that turns a laptop or an instrument
PC into a collection. The setup logs you in to Globus and asks for consent; the collection
it creates is the one you search for by name in the File Manager. Globus's install guides:
[Windows](https://docs.globus.org/globus-connect-personal/install/windows/),
[macOS](https://docs.globus.org/globus-connect-personal/install/mac/),
[Linux](https://docs.globus.org/globus-connect-personal/install/linux/). GCP has a
graphical interface on Windows and macOS, so Command Prompt and PowerShell make no
difference here.

### Windows

1. Download the installer from <https://app.globus.org/file-manager/gcp>, or directly as
   [globusconnectpersonal-latest.exe](https://downloads.globus.org/globus-connect-personal/windows/stable/globusconnectpersonal-latest.exe),
   and run it.
   Click **Install**; if you have no administrator rights, click **Browse** and choose a
   folder you may write to.
2. Click **Log In**, authenticate with Globus, grant the consents it asks for, and
   enter the details of your collection (its name is what you search for in the File
   Manager).
3. A circle with a "g" appears in the system tray (bottom right) while GCP runs.
   **Folders:** right-click that icon → **Options…** → the **Access** tab; the **+** icon
   adds a folder.

### macOS

1. Download Globus Connect Personal from <https://app.globus.org/file-manager/gcp> (or
   [globusconnectpersonal-latest.dmg](https://downloads.globus.org/globus-connect-personal/mac/stable/globusconnectpersonal-latest.dmg)
   directly), then open the installer and drag the icon onto **Applications**.
2. Open **Globus Connect Personal** from Applications, click **Log In**, authenticate,
   grant the consents, and enter the details of your collection.
3. A menu bar icon shows that GCP runs. **Folders:** click that icon → **Preferences…** →
   the **Access** tab; the **+** icon adds a folder.

### Linux

Download and unpack the tarball, then set it up and start it from the unpacked folder:

```bash
wget https://downloads.globus.org/globus-connect-personal/linux/stable/globusconnectpersonal-latest.tgz
tar xzf globusconnectpersonal-latest.tgz
cd globusconnectpersonal-*/                 # the folder tar created, e.g. globusconnectpersonal-3.3.1
./globusconnectpersonal -setup              # log in and name the collection
./globusconnectpersonal -start &            # start it
./globusconnectpersonal -status             # is it running?
./globusconnectpersonal -stop
```

If you unpacked an older version before, `cd` stops with "too many arguments": delete the
old folder (`rm -r globusconnectpersonal-<old version>`) or `cd` into the new one by name.
A second `wget` saves `globusconnectpersonal-latest.tgz.1`, so delete the old `.tgz` first.

The graphical interface needs Tcl/Tk (`sudo apt-get install tk tcllib` on Debian and
Ubuntu); `-start` runs without it. **Folders:** edit `~/.globusonline/lta/config-paths`,
one line per folder in the form `<path>,<sharing flag>,<write flag>` (1 or 0 each), for
example `~/,0,1` for your home folder, writable and not shareable, then `-stop` and
`-start &` again.

### Folders, running, and the free version

- **Which folders are visible.** By default only your home folder is (on Linux, read and
  write access to `~/`, without sharing); the system sections above say where to change
  it. Expose the folder you transfer from, and nothing more; an instrument PC should
  expose only the folder its data lands in.
- **It must be running.** The collection is reachable only while the program runs and the
  computer is on and online. A transfer that involves it is suspended while it is not, and
  resumes when it is back unless three or more days have passed
  ([tutorial](https://docs.globus.org/guides/tutorials/manage-files/transfer-files/)). For
  a long transfer, switch off sleep.
- **Free version.** A transfer between a Personal collection and a collection run by a site
  (a university, NERSC) needs no subscription
  ([FAQ](https://docs.globus.org/faq/globus-connect-endpoints/)). Sharing *from* a
  Personal collection needs a subscription, and so, according to that FAQ, does a transfer
  between two Personal collections (it needs a guest collection on one of them); another
  Globus FAQ describes that point differently. To move data between two laptops, copy
  through a site's collection, or ask an admin.

## 7. Sharing data with someone

To give a collaborator access to a folder without giving them an account on the machine,
create a **guest collection** on it
([sharing tutorial](https://docs.globus.org/guides/tutorials/manage-files/share-files/)):

1. In the File Manager, open the collection that holds the folder and select the folder.
2. Click **Share**, then **Add Guest Collection**, give it a name and click
   **Create Collection**.
3. Open the new collection's **Permissions** tab and **Add Permissions - Share With**: a
   user (by Globus identity or e-mail), a group, all logged-in users, or the public
   (anonymous). Choose read-only or read and write; the **Path** field restricts the
   permission to a subfolder. **Send E-mail** notifies the person.

Unless the share is public (anonymous), a collaborator must log in to Globus to use it.

One condition applies: **sharing works only on collections hosted on an endpoint that has a
Globus subscription** ("Sharing with guest collections is available on Globus endpoints
managed by an active Subscription"; on a Personal collection, you must be a member of a
subscription group). So this depends on the site: whether it offers sharing, from which
folders, and with which rights. For NERSC see
[Perlmutter page 3](perlmutter/03-storage-and-transfer.md#sharing-data-with-people-outside-nersc).

## 8. The command line

Everything above also works from a terminal with the **Globus CLI**, which is the way to
script or repeat transfers
([documentation](https://docs.globus.org/cli/)). Globus recommends installing it with
pipx; `uv tool install globus-cli` gives the same isolated installation and also needs
no Python of your own, so the steps below use uv first and pipx as the alternative.

### Install the CLI with uv

uv's installer is described on its
[installation page](https://docs.astral.sh/uv/getting-started/installation/). On every system,
if `globus` is not found after the steps below, `uv tool update-shell` adds uv's tool folder
to your `PATH`. [Perlmutter page 5](perlmutter/05-python-uv.md) introduces uv.

#### Windows

In Command Prompt or PowerShell, run uv's installer (the command starts PowerShell itself):

```
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Then open a **new** window, so that the updated `PATH` takes effect, and install the CLI:

```
uv tool install globus-cli
```

#### macOS

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Open a **new** terminal, then:

```bash
uv tool install globus-cli
```

#### Linux

Same as macOS:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Open a **new** terminal, then:

```bash
uv tool install globus-cli
```

### Install the CLI with pipx instead

If you already have Python 3.10 or newer, pipx works too, as the
[pipx installation page](https://pipx.pypa.io/stable/how-to/install-pipx.html) describes.
After `pipx ensurepath`, open a **new** terminal.

#### Windows

With pip (use `python3` instead of `py` if Python came from the Microsoft Store):

```
py -m pip install --user pipx
```

This often ends with a warning that `pipx.exe` is installed in a directory that is not
on the `PATH`. Go to that directory (`cd` to the folder the warning names) and run
`.\pipx.exe ensurepath`, even without the warning. Then, in a new window:

```
pipx install globus-cli
```

#### macOS

With [Homebrew](https://brew.sh/):

```bash
brew install pipx
pipx ensurepath
pipx install globus-cli          # in a new terminal
```

#### Linux

```bash
sudo apt update && sudo apt install pipx     # Ubuntu 23.04 or newer
sudo dnf install pipx                        # Fedora
pipx ensurepath
pipx install globus-cli                      # in a new terminal
```

On other distributions, `python3 -m pip install --user pipx` and then
`python3 -m pipx ensurepath`; on Ubuntu 23.04+, Debian 12+ and Fedora 38+ that pip
command fails with "externally-managed-environment", so use the distribution package.

### Using it

On Perlmutter the CLI is already available: `module load globus-tools`
([NERSC](https://docs.nersc.gov/services/globus/)). The commands are the same
everywhere:

```bash
globus login                                  # log in; follow what it prints
globus whoami                                 # which identity is logged in
globus endpoint search "NERSC DTN"            # find a collection and its ID
globus ls <collection-id>:/path/to/folder/    # list a folder, like the File Manager panel
globus transfer <source-id>:/path/ <dest-id>:/path/ --recursive --label "my data"
globus task list                              # your transfers, like the Activity page
globus task show <task-id>                    # one transfer's status
globus task wait <task-id>                    # block until it finishes
```

Collections are named by their ID (a UUID) here; `globus ls`, `transfer` and the options of
the table in section 5 are in the [command reference](https://docs.globus.org/cli/reference/).
As in the documentation's example, write a folder's path with a trailing `/` and add
`--recursive` to copy folders. The CLI keeps a login token on your machine: don't share it
or put it in a repository.

**NERSC.** The collections, paths, sign-in and sharing rules for our Perlmutter data are in
[Perlmutter page 3](perlmutter/03-storage-and-transfer.md#globus-large-data-many-files-or-unattended).
