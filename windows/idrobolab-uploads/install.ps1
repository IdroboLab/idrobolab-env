# install.ps1
# Installs the IdroboLab upload tool for the current Windows user:
#   - rclone, with winget, unless it is already installed
#   - idrobolab-uploads.ps1 and its icon in %LOCALAPPDATA%\IdroboLab\uploads
#   - the rclone remote "idrobolab_uploads" for the group's Google Drive, unless
#     it exists: asks for the client ID and secret of the group's Google OAuth
#     client (an admin hands them out), then opens a browser to log in. A remote
#     without a client ID of its own (set up by hand with rclone's shared client
#     ID) gets one, and logs in again.
#   - the desktop shortcut "IdroboLab Uploads"
#
# Run it from this folder, in Windows PowerShell:
#   powershell -ExecutionPolicy Bypass -File install.ps1
# Safe to run again: it repairs what is missing and replaces the copied files.

$ErrorActionPreference = "Stop"

$remote = "idrobolab_uploads"

function Find-Rclone {
    $cmd = Get-Command "rclone.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # a winget install does not reach the PATH of processes that are already running
    $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\rclone.exe"
    if (Test-Path $link) { return $link }
    return $null
}

# --- rclone ---
$rclone = Find-Rclone
if (-not $rclone) {
    Write-Host "Installing rclone with winget..."
    winget install --id Rclone.Rclone -e --accept-source-agreements --accept-package-agreements
    $rclone = Find-Rclone
    if (-not $rclone) {
        throw "rclone is not found after the winget install. Close this window, open a new PowerShell and run install.ps1 again."
    }
}
Write-Host "rclone: $rclone"

# --- script and icon ---
$installDir = Join-Path $env:LOCALAPPDATA "IdroboLab\uploads"
$installedScript = Join-Path $installDir "idrobolab-uploads.ps1"
$installedIcon = Join-Path $installDir "idrobolab-uploads.ico"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot "idrobolab-uploads.ps1") $installedScript
Copy-Item -Force (Join-Path $PSScriptRoot "..\..\assets\idrobolab-uploads.ico") $installedIcon
Write-Host "Installed to: $installDir"

# --- rclone remote ---
function Read-ClientCredentials {
    Write-Host ""
    Write-Host "Ask an admin for the client ID and client secret of the group's Google OAuth client."
    do { $id = (Read-Host "Client ID").Trim() } while (-not $id)
    do {
        $secure = Read-Host "Client secret" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $secret = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr).Trim() }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } while (-not $secret)
    return @{ Id = $id; Secret = $secret }
}

# The client_id of the remote, read from the line "client_id = ..." of its section
# in rclone.conf; no other line is read out or printed ("rclone config show" and
# "dump" would print the token).
function Get-RemoteClientId {
    $confPath = (& $rclone config file | Where-Object { $_ -match '\S' } | Select-Object -Last 1).Trim()
    $inRemote = $false
    $clientId = ""
    foreach ($line in Get-Content -LiteralPath $confPath) {
        if ($line -match '^\s*\[(.+)\]\s*$') { $inRemote = ($Matches[1] -eq $remote) }
        elseif ($inRemote -and $line -match '^\s*client_id\s*=\s*(.*)$') { $clientId = $Matches[1].Trim() }
    }
    return $clientId
}

$remotes = & $rclone listremotes
if ($remotes -notcontains "${remote}:") {
    $client = Read-ClientCredentials
    Write-Host ""
    Write-Host "A browser window opens: log in to the IdroboLab Google account (ask an admin for the login)."
    & $rclone config create $remote drive "client_id=$($client.Id)" "client_secret=$($client.Secret)" scope=drive.file
    if ($LASTEXITCODE -ne 0) {
        throw "rclone config create failed with exit code $LASTEXITCODE."
    }
} else {
    if (-not (Get-RemoteClientId)) {
        # set up by hand with rclone's shared client ID
        $client = Read-ClientCredentials
        Write-Host ""
        Write-Host "The remote ${remote}: uses rclone's shared Google client ID, which is being retired. Setting the group's client ID and logging in again."
        Write-Host "A browser window opens: log in to the IdroboLab Google account (ask an admin for the login)."
        & $rclone config update $remote "client_id=$($client.Id)" "client_secret=$($client.Secret)"
        if ($LASTEXITCODE -ne 0) {
            throw "rclone config update failed with exit code $LASTEXITCODE."
        }
    }
    # An interrupted "config create" leaves a remote without a login: test it
    # with a call whose output is discarded, and log in again if it fails.
    $ErrorActionPreference = "Continue"
    & $rclone lsf "${remote}:" --max-depth 1 --dirs-only 2>&1 | Out-Null
    $loginOk = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = "Stop"
    if ($loginOk) {
        Write-Host "rclone remote ${remote}: exists and works."
    } else {
        Write-Host ""
        Write-Host "Cannot reach the Drive with the saved login of ${remote}: (offline, or the login is missing or expired). Trying to log in again."
        Write-Host "A browser window opens: log in to the IdroboLab Google account (ask an admin for the login)."
        & $rclone config reconnect "${remote}:"
        if ($LASTEXITCODE -ne 0) {
            throw "rclone config reconnect failed with exit code $LASTEXITCODE."
        }
    }
}

# --- desktop shortcut ---
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "IdroboLab Uploads.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$installedScript`""
$shortcut.WorkingDirectory = $installDir
$shortcut.IconLocation = "$installedIcon,0"
$shortcut.Save()
Write-Host "Desktop shortcut: $shortcutPath"

Write-Host ""
Write-Host "Done. Double-click IdroboLab Uploads on the desktop."
