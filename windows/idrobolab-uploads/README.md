# IdroboLab Uploads (Windows)

A desktop shortcut that uploads folders, files or a Nion Swift project from a Windows
PC to the group's Google Drive. It is meant for the IdroboLab measurement PCs (Windows),
where several people share one Windows account: it asks for your name every time and
puts your uploads in a Drive folder of that name. Do not install it on other computers.
It uses [rclone](https://rclone.org/); the script `idrobolab-uploads.ps1` asks what to
upload (a window lets you pick it) and runs `rclone copy`.

On start it asks for your name, then for a mode:

| Key | Uploads |
|---|---|
| `F` | one folder, with its contents, as a folder of the same name |
| `L` | one or more files |
| `N` | a Nion Swift project: the `.nsproj` file and the folder `<project name> Data` next to it |

Uploads land in a folder of your name in the root of the group's Google Drive (the Drive
of the group's Google account): `<name>/<folder>/` for a folder, `<name>/` for files, and
for a Nion Swift project the `.nsproj` in `<name>/` and the data folder as
`<name>/<project name> Data/`. The name may not contain `/` or `\`, and is not
remembered between runs. The tool copies and never deletes anything. A file with the same
name in the same place, uploaded earlier by this tool, is overwritten when it differs
(Google Drive keeps the old version as a revision), and a folder with the same name is
merged with the existing one: two people who type the same name share a folder. The
folder is named exactly as typed (only leading and trailing spaces are removed), so
"Anna Muller" and "anna muller" are two folders: type your name the same way every
time. A name may not be `.` or `..` either. The
rclone remote asks Google for access to the files it creates itself only (scope
`drive.file`), so the tool cannot see or change other files in the Drive.

## Install

1. Get the repository: on its GitHub page choose **Code, Download ZIP** and unzip it,
   or clone it ([docs/02-cloning.md](../../docs/02-cloning.md)). GitHub cannot
   download a single folder.
2. In Windows PowerShell, go to the folder `windows\idrobolab-uploads\` of the repository
   (`install.ps1` needs `idrobolab-uploads.ps1` next to it and the icon
   `assets\idrobolab-uploads.ico` of the same copy of the repository)
   and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File install.ps1
   ```

   `install.ps1`:

   - installs rclone with `winget` (`winget install --id Rclone.Rclone -e`) unless it
     is already installed;
   - copies the script and the icon to `%LOCALAPPDATA%\IdroboLab\uploads\`;
   - unless the rclone remote `idrobolab_uploads` exists, asks for the **client ID** and
     **client secret** (the secret is not shown as you type) and runs
     `rclone config create idrobolab_uploads drive client_id=... client_secret=... scope=drive.file`,
     which opens a browser window: log in with the IdroboLab Google account. An admin
     hands out the client ID, the client secret and the login;
   - if the remote exists but has no client ID (a remote set up by hand with rclone's
     shared client ID, the earlier setup steps), asks for the two values, sets them with
     `rclone config update` and logs in again in the browser;
   - if the remote exists but cannot reach the Drive (offline, or its login is missing
     or has expired, for example after an interrupted setup), runs
     `rclone config reconnect` for it;
   - puts the shortcut **IdroboLab Uploads** on your desktop (also when the desktop is
     redirected to OneDrive).

   Running it again is safe: it repairs what is missing and replaces the copied files.
3. Double-click **IdroboLab Uploads**.

The client ID, the client secret and the login token stay in the rclone configuration
file of the Windows account (`rclone config file` prints its path, normally
`%APPDATA%\rclone\rclone.conf`). The file is not part of this repository, and nothing
here sends it anywhere. Do not copy it to others or commit it to git; anyone with the
file can read and write the files the tool created. Removing the remote
(`rclone config delete idrobolab_uploads`) logs out.

## Installed before? Switch to the group's client ID

The earlier setup steps (a remote set up by hand with rclone's shared Google client ID)
used a client ID that rclone is retiring during 2026. Run `install.ps1` again (see
above): it notices that the remote has no client ID, asks for the client ID and secret,
and logs in again. The `drive.file` scope is per app, so a login made with the new
client ID is expected to see only the files created with it. Files uploaded earlier stay
in the Drive and in its web interface, but rclone is not expected to see them any more:
uploading the same file again makes a second copy.

## For admins: the Google client

The client ID and secret belong to one OAuth client of the group's Google project, of
the type **Desktop app**, made as described in rclone's guide
(<https://rclone.org/drive/#making-your-own-client-id>). While the consent screen of the
project is in "Testing" status, Google lets the login tokens expire after seven days;
publish the app ("In production") to avoid that. Hand the ID and secret out to members
the same way as the account login, never in this repository.

## If an upload fails

If rclone reports an authorization or token error, or the browser login of the setup was
interrupted, log in again:

```powershell
rclone config reconnect idrobolab_uploads:
```

(The upload tool prints this command when rclone fails. If `rclone` is not found,
close PowerShell, open it again, or use the full path
`%LOCALAPPDATA%\Microsoft\WinGet\Links\rclone.exe`.) Running `install.ps1` again does
the same check.

## Set up rclone by hand

Instead of `install.ps1`, for example when `winget` is not available:

1. Install rclone from <https://rclone.org/downloads/>, or `winget install Rclone.Rclone`
   in PowerShell.
2. Create the remote interactively with `rclone config`. Enter the client secret at
   rclone's question, never as an argument of a command: an argument stays in the
   PowerShell history of the shared Windows account and in the process list. rclone
   numbers its menu entries differently between versions, so choose by the names below:

   | Question | Answer |
   |---|---|
   | `e/n/d/r/q>` | `n` (New remote) |
   | name | `idrobolab_uploads` |
   | Storage | `drive` (Google Drive) |
   | `client_id` | the client ID from an admin |
   | `client_secret` | the client secret from an admin |
   | `scope` | `drive.file` (access to files created by rclone only) |
   | `service_account_file` | leave empty |
   | Edit advanced config? | No (default) |
   | Use web browser to automatically authenticate? | Yes (default); log in with the IdroboLab Google account in the window that opens |
   | Configure this as a Shared Drive? | No (default) |
   | Keep this remote? | Yes (default) |

   For a remote set up earlier without a client ID, choose `e` (edit an existing remote)
   instead of `n`, select `idrobolab_uploads`, enter the client ID and secret at their
   questions, accept the defaults for the rest and log in again in the browser. Run
   `rclone config reconnect idrobolab_uploads:` if the
   upload then fails with a login error.
3. Put `idrobolab-uploads.ps1` somewhere and make a desktop shortcut whose target is

   ```
   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\idrobolab-uploads.ps1"
   ```

The script finds `rclone.exe` on the `PATH`, or else at
`%LOCALAPPDATA%\Microsoft\WinGet\Links\rclone.exe`, where `winget` puts it (a program
started before the installation does not see the new `PATH`).

## Files

| File | What |
|---|---|
| `install.ps1` | the installer described above |
| `idrobolab-uploads.ps1` | the upload tool |
| [`assets/idrobolab-uploads.ico`](../../assets/idrobolab-uploads.ico) (top of the repository) | the shortcut's icon; CC BY 4.0, see [assets/LICENSE](../../assets/LICENSE) |
