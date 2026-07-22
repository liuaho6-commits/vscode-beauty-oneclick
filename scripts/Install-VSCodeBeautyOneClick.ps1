param(
    [string]$ArchivePath = "",
    [string]$PayloadPath = "",
    [string]$UserDataPath = "",
    [string]$ExtensionsPath = "",
    [string]$FontsPath = "",
    [switch]$CleanFirst,
    [switch]$SkipVSCodeInstall,
    [switch]$SkipUserData,
    [switch]$SkipExtensions,
    [switch]$SkipFonts,
    [switch]$SkipWorkbenchCss,
    [switch]$ForceDownload
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$VSCodeDownloadUrl = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Value
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Resolve-ExistingPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return $null
}

function Get-CodeExe {
    $command = Get-Command code -ErrorAction SilentlyContinue
    if ($command) {
        $source = $command.Source
        if ($source -match "\\bin\\code(\.cmd)?$") {
            $root = Split-Path -Parent (Split-Path -Parent $source)
            $exe = Join-Path $root "Code.exe"
            if (Test-Path -LiteralPath $exe) {
                return (Resolve-Path -LiteralPath $exe).Path
            }
        }
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code\Code.exe"),
        $(if ($programFilesX86) { Join-Path $programFilesX86 "Microsoft VS Code\Code.exe" } else { $null }),
        "D:\Microsoft VS Code\Code.exe",
        "D:\VSCode-LocalClone\Code.exe"
    )

    foreach ($candidate in $candidates) {
        $resolved = Resolve-ExistingPath -Path $candidate
        if ($resolved) {
            return $resolved
        }
    }
    return $null
}

function Get-CodeCli {
    $command = Get-Command code -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $codeExe = Get-CodeExe
    if ($codeExe) {
        $cli = Join-Path (Split-Path -Parent $codeExe) "bin\code.cmd"
        if (Test-Path -LiteralPath $cli) {
            return $cli
        }
        return $codeExe
    }
    return $null
}

function Stop-VSCode {
    $processes = @(Get-Process Code -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Step "Stopping VS Code"
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Ok "Stopped $($processes.Count) Code process(es)."
}

function Assert-KnownCleanTarget {
    param([string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $knownTargets = @(
        (Join-Path $env:APPDATA "Code"),
        (Join-Path $env:LOCALAPPDATA "Code"),
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code"),
        (Join-Path $env:USERPROFILE ".vscode\extensions")
    ) | ForEach-Object { [System.IO.Path]::GetFullPath($_) }

    foreach ($target in $knownTargets) {
        if ($full -ieq $target) {
            return $full
        }
    }

    throw "Refusing to clean an unknown path: $Path"
}

function Backup-Or-RemovePath {
    param(
        [string]$Path,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $safePath = Assert-KnownCleanTarget -Path $Path
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $name = ($safePath -replace "[:\\]+", "_").Trim("_")
    $backup = Join-Path $BackupRoot $name

    if (Test-Path -LiteralPath $backup) {
        $backup = "$backup-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    }

    Write-Host "Move: $safePath"
    Write-Host "  To: $backup"
    Move-Item -LiteralPath $safePath -Destination $backup -Force
}

function Clean-StandardVSCodeState {
    Write-Step "Cleaning standard VS Code state"
    Stop-VSCode

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = Join-Path $env:USERPROFILE "Desktop\VSCode-Beauty-Backup-$stamp"

    Backup-Or-RemovePath -Path (Join-Path $env:APPDATA "Code") -BackupRoot $backupRoot
    Backup-Or-RemovePath -Path (Join-Path $env:LOCALAPPDATA "Code") -BackupRoot $backupRoot
    Backup-Or-RemovePath -Path (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code") -BackupRoot $backupRoot
    Backup-Or-RemovePath -Path (Join-Path $env:USERPROFILE ".vscode\extensions") -BackupRoot $backupRoot

    Write-Ok "Cleaned standard VS Code paths. Backup root: $backupRoot"
}

function Install-VSCode {
    if ($SkipVSCodeInstall) {
        Write-WarnLine "VS Code install skipped."
        return
    }

    $existing = Get-CodeExe
    if ($existing -and -not $ForceDownload) {
        Write-Ok "VS Code already exists: $existing"
        return
    }

    Write-Step "Installing fresh VS Code"
    $installer = Join-Path $env:TEMP "VSCodeUserSetup-x64-latest.exe"
    if ((-not (Test-Path -LiteralPath $installer)) -or $ForceDownload) {
        Write-Host "Download: $VSCodeDownloadUrl"
        Invoke-WebRequest -Uri $VSCodeDownloadUrl -OutFile $installer -UseBasicParsing
    }

    $args = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath"
    $process = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "VS Code installer failed with exit code $($process.ExitCode)."
    }

    for ($i = 0; $i -lt 30; $i++) {
        $codeExe = Get-CodeExe
        if ($codeExe) {
            Write-Ok "Installed VS Code: $codeExe"
            return
        }
        Start-Sleep -Seconds 1
    }

    throw "VS Code installation finished, but Code.exe was not found."
}

function Find-AdjacentArchive {
    $preferred = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "VSCode-FullStandardMigration-*.tar.zst" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($preferred.Count -gt 0) {
        return $preferred[0].FullName
    }

    $direct = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.tar.zst" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($direct.Count -gt 0) {
        return $direct[0].FullName
    }

    $dist = Join-Path $PSScriptRoot "dist"
    if (Test-Path -LiteralPath $dist) {
        $nestedPreferred = @(Get-ChildItem -LiteralPath $dist -Filter "VSCode-FullStandardMigration-*.tar.zst" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($nestedPreferred.Count -gt 0) {
            return $nestedPreferred[0].FullName
        }

        $nested = @(Get-ChildItem -LiteralPath $dist -Filter "*.tar.zst" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($nested.Count -gt 0) {
            return $nested[0].FullName
        }
    }
    return $null
}

function Get-PayloadRoot {
    if ($PayloadPath) {
        $resolvedPayload = Resolve-ExistingPath -Path $PayloadPath
        if (-not $resolvedPayload) {
            throw "PayloadPath does not exist: $PayloadPath"
        }

        if (Test-Path -LiteralPath (Join-Path $resolvedPayload "payload")) {
            return (Join-Path $resolvedPayload "payload")
        }
        return $resolvedPayload
    }

    $payloadBesideScript = Join-Path $PSScriptRoot "payload"
    if (Test-Path -LiteralPath $payloadBesideScript) {
        return $payloadBesideScript
    }

    if (-not $ArchivePath) {
        $ArchivePath = Find-AdjacentArchive
    }
    if (-not $ArchivePath) {
        return $null
    }

    $resolvedArchive = Resolve-ExistingPath -Path $ArchivePath
    if (-not $resolvedArchive) {
        throw "ArchivePath does not exist: $ArchivePath"
    }

    Write-Step "Extracting beauty payload"
    $extractRoot = Join-Path $env:TEMP ("VSCodeBeautyPayload-" + (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedArchive).Hash.Substring(0, 12))
    $payloadAfterExtract = Join-Path $extractRoot "payload"

    if (-not (Test-Path -LiteralPath $payloadAfterExtract)) {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        if (-not $tar) {
            throw "tar.exe was not found. Extract the archive manually, or pass -PayloadPath."
        }
        & $tar.Source -xf $resolvedArchive -C $extractRoot
        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe failed to extract: $resolvedArchive"
        }
    }

    if (-not (Test-Path -LiteralPath $payloadAfterExtract)) {
        throw "Extracted archive did not contain a payload folder."
    }

    Write-Ok "Payload: $payloadAfterExtract"
    return $payloadAfterExtract
}

function Resolve-OptionalSourcePath {
    param(
        [string]$Path,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $resolved = Resolve-ExistingPath -Path $Path
    if (-not $resolved) {
        throw "$Name does not exist: $Path"
    }

    return $resolved
}

function Get-RepositoryFontsRoot {
    $candidates = @(
        (Join-Path $PSScriptRoot "fonts"),
        (Join-Path (Split-Path -Parent $PSScriptRoot) "fonts")
    )

    foreach ($candidate in $candidates) {
        $resolved = Resolve-ExistingPath -Path $candidate
        if ($resolved) {
            return $resolved
        }
    }

    return $null
}

function Get-RepositoryRoot {
    $scriptLeaf = Split-Path -Leaf $PSScriptRoot
    if ($scriptLeaf -ieq "scripts") {
        return (Split-Path -Parent $PSScriptRoot)
    }
    return $PSScriptRoot
}

function Add-UniqueResolvedPath {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )

    $resolved = Resolve-ExistingPath -Path $Path
    if (-not $resolved) {
        return
    }

    foreach ($item in $List) {
        if ($item -ieq $resolved) {
            return
        }
    }
    $List.Add($resolved) | Out-Null
}

function Get-AutoProfileRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $repoRoot = Get-RepositoryRoot
    $repoParent = Split-Path -Parent $repoRoot
    $location = (Get-Location).Path

    $anchors = @($PSScriptRoot, $repoRoot, $repoParent, $location) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $profileNames = @("", "profile", "Profile", "VSCodeBeautyProfile", "vscode-profile", "VSCodeBeautySource", "source", "payload")

    foreach ($anchor in $anchors) {
        foreach ($name in $profileNames) {
            $candidate = if ([string]::IsNullOrWhiteSpace($name)) { $anchor } else { Join-Path $anchor $name }
            Add-UniqueResolvedPath -List $roots -Path $candidate
        }
    }

    return $roots
}

function Get-AutoSourcePath {
    param(
        [ValidateSet("UserData", "Extensions")]
        [string]$Kind
    )

    $relativePaths = if ($Kind -eq "UserData") {
        @("user-data", "Code", "AppData\Roaming\Code")
    }
    else {
        @("extensions", ".vscode\extensions")
    }

    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($root in Get-AutoProfileRoots) {
        foreach ($relativePath in $relativePaths) {
            $candidate = Join-Path $root $relativePath
            Add-UniqueResolvedPath -List $matches -Path $candidate
        }
    }

    if ($matches.Count -eq 0) {
        return $null
    }

    if ($matches.Count -gt 1) {
        Write-WarnLine "Multiple $Kind source candidates were found; pass -${Kind}Path explicitly."
        foreach ($match in $matches) {
            Write-WarnLine "  $match"
        }
        return $null
    }

    Write-Ok "Auto-detected ${Kind}: $($matches[0])"
    return $matches[0]
}

function Invoke-Robocopy {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExtraArgs = @()
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source does not exist: $Source"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $args = @($Source, $Destination, "/MIR", "/R:1", "/W:1", "/NFL", "/NDL", "/NP", "/NJH", "/NJS") + $ExtraArgs
    & robocopy.exe @args | Out-Host
    $exit = $LASTEXITCODE
    if ($exit -gt 7) {
        throw "robocopy failed with exit code $exit from '$Source' to '$Destination'."
    }
}

function Restore-UserData {
    param([string]$PayloadRoot)

    if ($SkipUserData) {
        Write-WarnLine "User data restore skipped."
        return
    }

    $source = Resolve-OptionalSourcePath -Path $UserDataPath -Name "UserDataPath"
    if (-not $source -and $PayloadRoot) {
        $candidate = Join-Path $PayloadRoot "user-data"
        if (Test-Path -LiteralPath $candidate) {
            $source = (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    if (-not $source) {
        $source = Get-AutoSourcePath -Kind "UserData"
    }
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        Write-WarnLine "No user-data source found."
        return
    }

    Write-Step "Restoring VS Code user data"
    Stop-VSCode
    $target = Join-Path $env:APPDATA "Code"
    Invoke-Robocopy -Source $source -Destination $target

    foreach ($lockFile in @("code.lock", "SingletonCookie", "SingletonLock", "SingletonSocket")) {
        $path = Join-Path $target $lockFile
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Ok "Restored: $target"
}

function Restore-Extensions {
    param([string]$PayloadRoot)

    if ($SkipExtensions) {
        Write-WarnLine "Extension restore skipped."
        return
    }

    $source = Resolve-OptionalSourcePath -Path $ExtensionsPath -Name "ExtensionsPath"
    if (-not $source -and $PayloadRoot) {
        $candidate = Join-Path $PayloadRoot "extensions"
        if (Test-Path -LiteralPath $candidate) {
            $source = (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    if (-not $source) {
        $source = Get-AutoSourcePath -Kind "Extensions"
    }
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        Write-WarnLine "No extension source found."
        return
    }

    Write-Step "Restoring VS Code extensions"
    $target = Join-Path $env:USERPROFILE ".vscode\extensions"
    Invoke-Robocopy -Source $source -Destination $target
    Write-Ok "Restored: $target"
}

function Get-VSCodeRipgrepExe {
    $codeExe = Get-CodeExe
    if (-not $codeExe) {
        return $null
    }

    $root = Split-Path -Parent $codeExe
    $rgFiles = @(Get-ChildItem -LiteralPath $root -Recurse -Filter "rg.exe" -File -ErrorAction SilentlyContinue)
    if ($rgFiles.Count -eq 0) {
        return $null
    }

    $preferred = $rgFiles |
        Where-Object { $_.FullName -like "*@vscode*ripgrep*" } |
        Select-Object -First 1
    if ($preferred) {
        return $preferred.FullName
    }

    return $rgFiles[0].FullName
}

function Configure-TodoTreeRipgrep {
    $extensionsRoot = Join-Path $env:USERPROFILE ".vscode\extensions"
    if (-not (Test-Path -LiteralPath $extensionsRoot)) {
        return
    }

    $todoTree = Get-ChildItem -LiteralPath $extensionsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "gruntfuggly.todo-tree-*" } |
        Select-Object -First 1
    if (-not $todoTree) {
        return
    }

    $rgExe = Get-VSCodeRipgrepExe
    if (-not $rgExe) {
        Write-WarnLine "Todo Tree is installed, but rg.exe was not found."
        return
    }

    Write-Step "Configuring Todo Tree ripgrep path"
    $settingsDir = Join-Path $env:APPDATA "Code\User"
    $settingsPath = Join-Path $settingsDir "settings.json"
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-Utf8NoBom -Path $settingsPath -Value "{}"
    }

    $raw = Get-Content -LiteralPath $settingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = "{}"
    }

    try {
        $settings = $raw | ConvertFrom-Json
    }
    catch {
        Write-WarnLine "settings.json is not plain JSON; Todo Tree ripgrep path was not written."
        return
    }

    if ($null -eq $settings) {
        $settings = [pscustomobject]@{}
    }

    Set-ObjectProperty -Object $settings -Name "todo-tree.ripgrep" -Value $rgExe
    $settingsJson = $settings | ConvertTo-Json -Depth 100
    Write-Utf8NoBom -Path $settingsPath -Value ($settingsJson + [Environment]::NewLine)
    Write-Ok "todo-tree.ripgrep: $rgExe"
}

function Ensure-FontNativeMethods {
    if ("Win32.FontNativeMethods" -as [type]) {
        return
    }

    Add-Type -Namespace Win32 -Name FontNativeMethods -MemberDefinition @"
[DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int AddFontResourceW(string lpFileName);

[DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern bool RemoveFontResourceW(string lpFileName);

[DllImport("user32.dll", SetLastError=true)]
public static extern int SendMessageTimeout(
    System.IntPtr hWnd,
    int Msg,
    System.IntPtr wParam,
    System.IntPtr lParam,
    int fuFlags,
    int uTimeout,
    out System.IntPtr lpdwResult);
"@
}

function Send-FontChangeBroadcast {
    try {
        Ensure-FontNativeMethods
        $result = [IntPtr]::Zero
        [Win32.FontNativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1000, [ref]$result) | Out-Null
    }
    catch {
        Write-WarnLine "Font-change broadcast failed; log off/on or restart Windows if an app cannot see font changes."
    }
}

function Get-FontRegistryValueName {
    param([System.IO.FileInfo]$Font)

    $kind = if ($Font.Extension -ieq ".ttc") { "TrueType Collection" } else { "TrueType" }
    return "$($Font.BaseName) ($kind)"
}

function Install-CurrentUserFonts {
    param([string]$PayloadRoot)

    if ($SkipFonts) {
        Write-WarnLine "Font install skipped."
        return
    }

    $source = Resolve-OptionalSourcePath -Path $FontsPath -Name "FontsPath"
    if (-not $source -and $PayloadRoot) {
        $candidate = Join-Path $PayloadRoot "fonts"
        if (Test-Path -LiteralPath $candidate) {
            $source = (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    if (-not $source) {
        $source = Get-RepositoryFontsRoot
    }
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        Write-WarnLine "No font source found."
        return
    }

    Write-Step "Installing fonts for current user only"
    Write-WarnLine "This step writes HKCU and %LOCALAPPDATA%\Microsoft\Windows\Fonts only."

    $fontFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".ttf", ".ttc", ".otf") })
    if ($fontFiles.Count -eq 0) {
        Write-WarnLine "No font files found."
        return
    }

    Ensure-FontNativeMethods
    $target = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    if (-not (Test-Path -LiteralPath $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    $installedCount = 0
    foreach ($font in $fontFiles) {
        $targetPath = Join-Path $target $font.Name
        Copy-Item -LiteralPath $font.FullName -Destination $targetPath -Force
        $valueName = Get-FontRegistryValueName -Font $font
        New-ItemProperty -Path $regPath -Name $valueName -Value $targetPath -PropertyType String -Force | Out-Null
        [Win32.FontNativeMethods]::AddFontResourceW($targetPath) | Out-Null
        $installedCount++
    }

    Send-FontChangeBroadcast
    Write-Ok "Installed/refreshed $installedCount of $($fontFiles.Count) font file(s) for current user."
}

function Get-VSCodeWorkbenchCssPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    $candidates = New-Object System.Collections.Generic.List[string]
    $roots = New-Object System.Collections.Generic.List[string]

    $codeExe = Get-CodeExe
    if ($codeExe) {
        $root = Split-Path -Parent $codeExe
        if (-not $roots.Contains($root)) {
            $roots.Add($root)
        }
        $candidates.Add((Join-Path $root "resources\app\out\vs\workbench\workbench.desktop.main.css"))
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    foreach ($candidateRoot in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code"),
        $(if ($programFilesX86) { Join-Path $programFilesX86 "Microsoft VS Code" } else { $null }),
        "D:\Microsoft VS Code",
        "D:\VSCode-LocalClone"
    )) {
        if ($candidateRoot -and (Test-Path -LiteralPath $candidateRoot)) {
            $resolvedRoot = (Resolve-Path -LiteralPath $candidateRoot).Path
            if (-not $roots.Contains($resolvedRoot)) {
                $roots.Add($resolvedRoot)
            }
        }
    }

    foreach ($root in $roots) {
        $candidates.Add((Join-Path $root "resources\app\out\vs\workbench\workbench.desktop.main.css"))

        $versionedCssFiles = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                Join-Path $_.FullName "resources\app\out\vs\workbench\workbench.desktop.main.css"
            } |
            Where-Object { Test-Path -LiteralPath $_ }

        foreach ($cssFile in $versionedCssFiles) {
            $candidates.Add($cssFile)
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            if (-not $paths.Contains($resolved)) {
                $paths.Add($resolved)
            }
        }
    }

    return $paths
}

function Patch-WorkbenchCss {
    if ($SkipWorkbenchCss) {
        Write-WarnLine "Workbench CSS patch skipped."
        return
    }

    Write-Step "Patching VS Code workbench CSS font rules"
    $cssPaths = @(Get-VSCodeWorkbenchCssPaths)
    if ($cssPaths.Count -eq 0) {
        Write-WarnLine "No workbench.desktop.main.css was found."
        return
    }

    $markerStart = "/* vscode-beauty-oneclick start */"
    $markerEnd = "/* vscode-beauty-oneclick end */"
    $oldMarkerStart = "/* vscode-beautify-auto start */"
    $oldMarkerEnd = "/* vscode-beautify-auto end */"
    $safeMarkerStart = "/* vscode-beauty-safe start */"
    $safeMarkerEnd = "/* vscode-beauty-safe end */"

    $cssBlock = @"

$markerStart
.monaco-workbench,
.monaco-workbench .part,
.monaco-workbench .monaco-list,
.monaco-workbench .monaco-tree,
.monaco-workbench .monaco-inputbox,
.monaco-workbench .monaco-select-box,
.monaco-workbench .monaco-button,
.monaco-workbench .pane-header,
.monaco-workbench .tabs-container,
.monaco-workbench .monaco-label,
.monaco-workbench .label-name,
.monaco-workbench .label-description,
.monaco-workbench .monaco-highlighted-label,
.shadow-root-host {
    font-family: Inter, HarmonyOS Sans SC, "Segoe WPC", "Segoe UI", sans-serif;
}
.monaco-workbench .codicon,
.monaco-workbench .codicon[class*="codicon-"],
.monaco-workbench .action-label.codicon,
.monaco-workbench .monaco-action-bar .action-label.codicon {
    font-family: codicon !important;
}
.monaco-editor,
.monaco-editor .view-line,
.monaco-editor .margin,
.monaco-editor .minimap,
.monaco-workbench .integrated-terminal {
    font-family: JetBrains Mono, HarmonyOS Sans SC, Consolas, "Courier New", monospace;
}
$markerEnd
"@

    foreach ($cssPath in $cssPaths) {
        Write-Host "Target: $cssPath"
        $content = Get-Content -LiteralPath $cssPath -Raw
        $newContent = $content

        foreach ($pair in @(
            @($markerStart, $markerEnd),
            @($oldMarkerStart, $oldMarkerEnd),
            @($safeMarkerStart, $safeMarkerEnd)
        )) {
            while ($newContent.Contains($pair[0])) {
                $pattern = [regex]::Escape($pair[0]) + ".*?" + [regex]::Escape($pair[1]) + "\s*"
                $newContent = [regex]::Replace(
                    $newContent,
                    $pattern,
                    "",
                    [System.Text.RegularExpressions.RegexOptions]::Singleline
                )
            }
        }

        $newContent = $newContent.TrimEnd() + $cssBlock + [Environment]::NewLine

        $backup = "$cssPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $cssPath -Destination $backup -Force
        Write-Utf8NoBom -Path $cssPath -Value $newContent
        Write-Ok "Patched CSS. Backup: $backup"
        Update-VSCodeProductChecksum -CssPath $cssPath
    }
}

function Get-Base64Sha256NoPadding {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return [Convert]::ToBase64String($sha).TrimEnd("=")
}

function Set-ObjectProperty {
    param(
        [pscustomobject]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Update-VSCodeProductChecksum {
    param([string]$CssPath)

    $needle = [System.IO.Path]::DirectorySeparatorChar + "resources" +
        [System.IO.Path]::DirectorySeparatorChar + "app" +
        [System.IO.Path]::DirectorySeparatorChar + "out" +
        [System.IO.Path]::DirectorySeparatorChar

    $fullCssPath = [System.IO.Path]::GetFullPath($CssPath)
    $index = $fullCssPath.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) {
        Write-WarnLine "Could not derive product.json path for checksum update."
        return
    }

    $appRoot = $fullCssPath.Substring(0, $index + $needle.Length - 5)
    $productPath = Join-Path $appRoot "product.json"
    if (-not (Test-Path -LiteralPath $productPath)) {
        Write-WarnLine "product.json was not found for checksum update: $productPath"
        return
    }

    $relativeKey = $fullCssPath.Substring($index + $needle.Length).Replace("\", "/")
    $newChecksum = Get-Base64Sha256NoPadding -Path $fullCssPath

    $product = Get-Content -LiteralPath $productPath -Raw | ConvertFrom-Json
    if ($null -eq $product.checksums) {
        Write-WarnLine "product.json does not contain a checksums object."
        return
    }

    Set-ObjectProperty -Object $product.checksums -Name $relativeKey -Value $newChecksum
    $backup = "$productPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $productPath -Destination $backup -Force
    $productJson = $product | ConvertTo-Json -Depth 100
    Write-Utf8NoBom -Path $productPath -Value ($productJson + [Environment]::NewLine)
    Write-Ok "Updated product checksum: $relativeKey"
}

function New-VSCodeShortcut {
    $codeExe = Get-CodeExe
    if (-not $codeExe) {
        return
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) {
        return
    }

    $shortcutPath = Join-Path $desktop "Visual Studio Code.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $codeExe
    $shortcut.WorkingDirectory = Split-Path -Parent $codeExe
    $shortcut.IconLocation = "$codeExe,0"
    $shortcut.Save()
    Write-Ok "Shortcut: $shortcutPath -> $codeExe"
}

function Test-FontRegistry {
    param([string]$Name)

    $hits = @()
    $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    if (Test-Path -LiteralPath $regPath) {
        $hits = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).PSObject.Properties |
            Where-Object { $_.Name -like "*$Name*" } |
            Select-Object -ExpandProperty Name
    }
    return ($hits -join "; ")
}

function Show-Verification {
    Write-Step "Verification"

    $codeExe = Get-CodeExe
    if ($codeExe) {
        Write-Host "Code.exe: $codeExe"
        $codeCli = Get-CodeCli
        try {
            if ($codeCli) {
                $version = & $codeCli --version
                Write-Host "Version:"
                $version | ForEach-Object { Write-Host "  $_" }
            }
            else {
                Write-WarnLine "VS Code CLI was not found, so version output was skipped."
            }
        }
        catch {
            Write-WarnLine "Could not read VS Code version: $($_.Exception.Message)"
        }
    }
    else {
        Write-WarnLine "Code.exe was not found."
    }

    $settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    if (Test-Path -LiteralPath $settingsPath) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $settingsPath).Hash
        Write-Host "settings.json SHA256: $hash"

        $raw = Get-Content -LiteralPath $settingsPath -Raw
        foreach ($key in @("editor.fontFamily", "workbench.iconTheme", "workbench.colorTheme")) {
            if ($raw -match ('"' + [regex]::Escape($key) + '"\s*:\s*"([^"]*)"')) {
                Write-Host "${key}: $($Matches[1])"
            }
            else {
                Write-Host "${key}: <not set>"
            }
        }
    }
    else {
        Write-WarnLine "settings.json was not found."
    }

    $extensions = Join-Path $env:USERPROFILE ".vscode\extensions"
    if (Test-Path -LiteralPath $extensions) {
        $dirs = @(Get-ChildItem -LiteralPath $extensions -Directory -ErrorAction SilentlyContinue)
        Write-Host "Extension directories: $($dirs.Count)"
        $keyExtensions = $dirs |
            Where-Object { $_.Name -like "*jetbrains*" -or $_.Name -like "*darcula*" } |
            Select-Object -ExpandProperty Name
        Write-Host "Key extensions: $($keyExtensions -join ', ')"
    }
    else {
        Write-WarnLine "Extension folder was not found."
    }

    $cssPaths = @(Get-VSCodeWorkbenchCssPaths)
    foreach ($css in $cssPaths) {
        $hasMarker = (Get-Content -LiteralPath $css -Raw).Contains("vscode-beauty-oneclick")
        Write-Host "CSS marker: $hasMarker ($css)"
    }

    foreach ($font in @("JetBrains", "HarmonyOS", "Inter")) {
        $hit = Test-FontRegistry -Name $font
        if ($hit) {
            Write-Host "HKCU font registry [$font]: present"
        }
        else {
            Write-WarnLine "HKCU font registry [$font]: not found"
        }
    }
}

Write-Host "VS Code Beauty One-Click" -ForegroundColor Magenta
Write-Host "Script: $PSCommandPath"
Write-WarnLine "Fonts are installed for the current user only. HKLM and C:\Windows\Fonts are not modified."

if ($CleanFirst) {
    Clean-StandardVSCodeState
}

Install-VSCode
$payloadRoot = Get-PayloadRoot
Install-CurrentUserFonts -PayloadRoot $payloadRoot
Restore-UserData -PayloadRoot $payloadRoot
Restore-Extensions -PayloadRoot $payloadRoot
Configure-TodoTreeRipgrep
Patch-WorkbenchCss
New-VSCodeShortcut
Show-Verification

Write-Host ""
Write-Ok "Done. Close and reopen VS Code to see the final style."
