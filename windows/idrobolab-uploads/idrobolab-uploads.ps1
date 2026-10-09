# idrobolab-uploads.ps1
# Uploads files and folders to the IdroboLab Google Drive with rclone.
# Modes:
#   F = upload folder
#   L = upload files
#   N = upload NionSwift project (.nsproj + "<project_name> Data" folder)
#
# Assumes:
#   - rclone installed: on PATH, or at the link winget creates in
#     %LOCALAPPDATA%\Microsoft\WinGet\Links
#   - rclone remote "idrobolab_uploads:" configured for the group's Google Drive
#     (install.ps1 does this, README.md has the manual steps). The remote is the
#     root of that Drive.
#
# Asks for the person's name at every start (several people share one Windows
# account) and uploads everything into the Drive folder of that name:
# <name>/<folder>/ for F, <name>/ for the files of L, and <name>/ with the
# .nsproj and <name>/<project_name> Data/ for N.

Add-Type -AssemblyName System.Windows.Forms

$rcloneExe = "rclone.exe"
if (-not (Get-Command $rcloneExe -ErrorAction SilentlyContinue)) {
    # a winget install does not reach the PATH of processes that are already running
    $wingetLink = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\rclone.exe"
    if (Test-Path $wingetLink) { $rcloneExe = $wingetLink }
}
$remote   = "idrobolab_uploads"    # rclone remote of the group's Google Drive
$rcloneCommand = if ($rcloneExe -eq "rclone.exe") { "rclone" } else { "& `"$rcloneExe`"" }
$reconnectHint = "If the login to Google has expired or is incomplete, run: $rcloneCommand config reconnect ${remote}:"

Write-Host "Upload to Google Drive (Uploads)"
do {
    $person = (Read-Host "Your name (your uploads go to the Drive folder of this name)").Trim()
    if (-not $person) {
        Write-Host "Please enter your name."
    } elseif ($person -match '[/\\]' -or $person -match '^\.\.?$') {
        Write-Host "The name must not contain / or \, and must not be . or .."
        $person = ""
    }
} while (-not $person)
Write-Host ""
Write-Host "[F] Folder upload"
Write-Host "[L] File upload"
Write-Host "[N] NionSwift project upload"
$mode = Read-Host "Choose mode (F/L/N)"

if ($mode -match '^[Ff]') {
    # --- Folder mode ---
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the folder to upload to Google Drive (Uploads)"
    $dialog.ShowNewFolderButton = $false

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "No folder selected. Exiting..."
        Read-Host -Prompt "Press Enter to close."
        exit 1
    }

    $sourcePath = $dialog.SelectedPath
    Write-Host "Uploading folder: $sourcePath"

    $folderName = Split-Path -Leaf $sourcePath
    & $rcloneExe copy $sourcePath "${remote}:${person}/${folderName}/" --create-empty-src-dirs --log-level INFO -P

    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        Write-Host "Folder upload finished successfully."
    } else {
        Write-Host "Folder upload failed with exit code $exitCode."
        Write-Host $reconnectHint
    }
    Read-Host -Prompt "Press Enter to close."

} elseif ($mode -match '^[Ll]') {
    # --- File mode ---
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select file(s) to upload to Google Drive (Uploads)"
    $dialog.Multiselect = $true
    $dialog.Filter = "All files (*.*)|*.*"

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "No files selected. Exiting..."
        Read-Host -Prompt "Press Enter to close."
        exit 1
    }

    $files = $dialog.FileNames

    $anyFailed = $false
    foreach ($file in $files) {
        Write-Host "Uploading file: $file"
        & $rcloneExe copy $file "${remote}:${person}/" --log-level INFO -P
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            Write-Host "  -> failed with exit code $code"
            $anyFailed = $true
        }
    }
    if ($anyFailed) { Write-Host $reconnectHint }
    Write-Host "File upload(s) done."
    Read-Host -Prompt "Press Enter to close."

} elseif ($mode -match '^[Nn]') {
    # --- NionSwift project mode ---
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select the NionSwift project (.nsproj)"
    $dialog.Multiselect = $false
    $dialog.Filter = "NionSwift project (*.nsproj)|*.nsproj|All files (*.*)|*.*"

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "No project file selected. Exiting..."
        Read-Host -Prompt "Press Enter to close."
        exit 1
    }

    $projFile = $dialog.FileName
    Write-Host "Selected project file: $projFile"

    # Get directory containing the .nsproj and the project name without extension
    $projDir  = Split-Path -Path $projFile -Parent       # e.g. C:\data\proj1
    $projName = Split-Path -Path $projFile -Leaf         # e.g. proj1.nsproj
    $projName = [System.IO.Path]::GetFileNameWithoutExtension($projName)  # proj1

    # Nion Swift names the data folder "<projName> Data". Windows ignores case, so
    # take the folder's real name: it becomes the folder name in the Drive.
    $dataDir = Get-ChildItem -LiteralPath $projDir -Directory |
        Where-Object { $_.Name -eq "$projName Data" } |
        Select-Object -First 1

    if (-not $dataDir) {
        $expectedDataDir = Join-Path -Path $projDir -ChildPath "$projName Data"
        Write-Host "ERROR: Expected data directory not found:"
        Write-Host "  $expectedDataDir"
        Write-Host "Aborting NionSwift project upload."
        Read-Host -Prompt "Press Enter to close."
        exit 1
    }

    $dataDirPath = $dataDir.FullName    # e.g. C:\data\proj1 Data

    Write-Host "Project directory: $projDir"
    Write-Host "Data directory:    $dataDirPath"
    Write-Host ""

    # Upload the .nsproj file
    Write-Host "Uploading project file..."
    & $rcloneExe copy $projFile "${remote}:${person}/" --log-level INFO -P
    $code1 = $LASTEXITCODE

    # Upload the data directory (contents)
    Write-Host "Uploading data directory..."
    $folderName = Split-Path -Leaf $dataDirPath
    & $rcloneExe copy $dataDirPath "${remote}:${person}/${folderName}/" --create-empty-src-dirs --log-level INFO -P
    $code2 = $LASTEXITCODE

    if ($code1 -eq 0 -and $code2 -eq 0) {
        Write-Host "NionSwift project upload finished successfully."
    } else {
        Write-Host "NionSwift project upload had errors. Codes: file=$code1, data=$code2"
        Write-Host $reconnectHint
    }

    Read-Host -Prompt "Press Enter to close."

} else {
    Write-Host "Invalid choice. Please run again and select F, L, or N."
    Read-Host -Prompt "Press Enter to close."
    exit 1
}
