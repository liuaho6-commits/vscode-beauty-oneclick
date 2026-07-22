param(
    [string]$PayloadPath = "",
    [string]$FontsPath = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

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

function Ensure-FontNativeMethods {
    if ("Win32.FontNativeMethods" -as [type]) {
        return
    }

    Add-Type -Namespace Win32 -Name FontNativeMethods -MemberDefinition @"
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

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

function Get-FontsRoot {
    $resolved = Resolve-ExistingPath -Path $FontsPath
    if ($resolved) {
        return $resolved
    }

    $resolvedPayload = Resolve-ExistingPath -Path $PayloadPath
    if ($resolvedPayload) {
        $candidate = Join-Path $resolvedPayload "fonts"
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $repoFonts = Get-RepositoryFontsRoot
    if ($repoFonts) {
        return $repoFonts
    }

    throw "Pass -FontsPath, pass -PayloadPath, or place this script in a repository with a fonts folder."
}

function Get-BeautyFontInventory {
    $fontRoot = Get-FontsRoot
    if (-not (Test-Path -LiteralPath $fontRoot)) {
        throw "Font source not found: $fontRoot"
    }

    $fontFiles = @(Get-ChildItem -LiteralPath $fontRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".ttf", ".ttc", ".otf") })
    if ($fontFiles.Count -eq 0) {
        throw "No font files found in payload: $fontRoot"
    }

    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($font in $fontFiles) {
        [void]$names.Add($font.Name)
    }

    [pscustomobject]@{
        Files = $fontFiles
        FileNames = $names
        Families = @("JetBrains Mono", "HarmonyOS Sans SC", "Inter")
    }
}

function Test-BeautyFontRegistryValue {
    param(
        [System.Management.Automation.PSPropertyInfo]$Property,
        [object]$Inventory
    )

    foreach ($family in $Inventory.Families) {
        if ($Property.Name -like "*$family*") {
            return $true
        }
    }

    $value = [string]$Property.Value
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $fileName = Split-Path -Leaf $value
        if ($Inventory.FileNames.Contains($fileName)) {
            return $true
        }
    }

    return $false
}

function Remove-BeautyFontRegistryValues {
    param([object]$Inventory)

    Write-Step "Removing beauty font registry values"
    foreach ($regPath in @(
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    )) {
        if (-not (Test-Path -LiteralPath $regPath)) {
            continue
        }

        $props = (Get-ItemProperty -Path $regPath).PSObject.Properties |
            Where-Object { $_.MemberType -eq "NoteProperty" -and (Test-BeautyFontRegistryValue -Property $_ -Inventory $Inventory) }

        foreach ($prop in $props) {
            try {
                Write-Host "Remove registry: $regPath -> $($prop.Name)"
                Remove-ItemProperty -Path $regPath -Name $prop.Name -Force
            }
            catch {
                Write-WarnLine "Could not remove registry value: $regPath -> $($prop.Name)"
                Write-WarnLine $_.Exception.Message
            }
        }
    }
}

function Remove-BeautyFontFiles {
    param(
        [object]$Inventory,
        [string]$BackupRoot
    )

    Write-Step "Removing beauty font files"
    Ensure-FontNativeMethods

    foreach ($base in @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"),
        (Join-Path $env:WINDIR "Fonts")
    )) {
        foreach ($fileName in $Inventory.FileNames) {
            $path = Join-Path $base $fileName
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }

            for ($i = 0; $i -lt 10; $i++) {
                if (-not [Win32.FontNativeMethods]::RemoveFontResourceW($path)) {
                    break
                }
            }

            try {
                $backupDir = Join-Path $BackupRoot ("fonts-" + (($base -replace "[:\\]+", "_").Trim("_")))
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                Copy-Item -LiteralPath $path -Destination (Join-Path $backupDir $fileName) -Force
                Remove-Item -LiteralPath $path -Force
                Write-Host "Removed font file: $path"
            }
            catch {
                Write-WarnLine "Could not remove font file: $path"
                Write-WarnLine $_.Exception.Message
            }
        }
    }

    Send-FontChangeBroadcast
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

function Move-KnownPath {
    param(
        [string]$Path,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Missing: $Path"
        return
    }

    $full = [System.IO.Path]::GetFullPath($Path)
    $allowed = @(
        [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code")),
        [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA "Code")),
        [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Code")),
        [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".vscode"))
    )

    if (-not ($allowed | Where-Object { $_ -ieq $full })) {
        throw "Refusing to move unexpected path: $full"
    }

    $name = ($full -replace "[:\\]+", "_").Trim("_")
    $destination = Join-Path $BackupRoot $name
    if (Test-Path -LiteralPath $destination) {
        $destination = "$destination-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    }

    Write-Host "Move: $full"
    Write-Host "  To: $destination"
    Move-Item -LiteralPath $full -Destination $destination -Force
}

function Uninstall-VSCode {
    Write-Step "Uninstalling VS Code"
    Stop-VSCode

    $uninstallers = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\unins000.exe"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code\unins000.exe")
    )

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86) {
        $uninstallers += Join-Path $programFilesX86 "Microsoft VS Code\unins000.exe"
    }

    $uninstaller = $uninstallers | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($uninstaller) {
        Write-Host "Run: $uninstaller"
        $process = Start-Process -FilePath $uninstaller -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru -WindowStyle Hidden
        Write-Host "Exit code: $($process.ExitCode)"
        Start-Sleep -Seconds 3
    }
    else {
        Write-Host "VS Code uninstaller not found."
    }
}

function Clear-VSCodeActivePaths {
    param([string]$BackupRoot)

    Write-Step "Moving VS Code active paths out of the profile"
    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code"),
        (Join-Path $env:APPDATA "Code"),
        (Join-Path $env:LOCALAPPDATA "Code"),
        (Join-Path $env:USERPROFILE ".vscode")
    )) {
        Move-KnownPath -Path $path -BackupRoot $BackupRoot
    }
}

function Show-ResetVerification {
    param([object]$Inventory)

    Write-Step "Reset verification"
    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code"),
        (Join-Path $env:APPDATA "Code"),
        (Join-Path $env:LOCALAPPDATA "Code"),
        (Join-Path $env:USERPROFILE ".vscode")
    )) {
        Write-Host ("VSCodePath|{0}|{1}" -f (Test-Path -LiteralPath $path), $path)
    }

    foreach ($base in @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"),
        (Join-Path $env:WINDIR "Fonts")
    )) {
        $left = @()
        foreach ($fileName in $Inventory.FileNames) {
            $path = Join-Path $base $fileName
            if (Test-Path -LiteralPath $path) {
                $left += $path
            }
        }
        Write-Host ("FontFilesLeft|{0}|{1}" -f $left.Count, $base)
        foreach ($item in $left) {
            Write-Host "  $item"
        }
    }

    foreach ($regPath in @(
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    )) {
        if (-not (Test-Path -LiteralPath $regPath)) {
            Write-Host "FontRegLeft|0|$regPath"
            continue
        }
        $props = (Get-ItemProperty -Path $regPath).PSObject.Properties |
            Where-Object { $_.MemberType -eq "NoteProperty" -and (Test-BeautyFontRegistryValue -Property $_ -Inventory $Inventory) }
        Write-Host ("FontRegLeft|{0}|{1}" -f @($props).Count, $regPath)
        foreach ($prop in $props) {
            Write-Host "  $($prop.Name)=$($prop.Value)"
        }
    }
}

Write-Host "VS Code Beauty Lab Reset" -ForegroundColor Magenta
if ([string]::IsNullOrWhiteSpace($PayloadPath)) {
    $candidatePayload = Join-Path $PSScriptRoot "payload"
    if (Test-Path -LiteralPath $candidatePayload) {
        $PayloadPath = $candidatePayload
    }
}

if (-not [string]::IsNullOrWhiteSpace($PayloadPath)) {
    $PayloadPath = (Resolve-Path -LiteralPath $PayloadPath).Path
    Write-Host "Payload: $PayloadPath"
}
if (-not (Test-IsAdmin)) {
    Write-WarnLine "Not running as Administrator; HKLM and C:\Windows\Fonts cleanup may fail."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$baseForBackup = if ($PayloadPath) { $PayloadPath } else { $PSScriptRoot }
$payloadParent = Split-Path -Parent $baseForBackup
$distRoot = Split-Path -Parent $payloadParent
if ([string]::IsNullOrWhiteSpace($distRoot)) {
    $distRoot = Join-Path $env:TEMP "VSCodeBeautyLab"
}
$backupRoot = Join-Path $distRoot "VSCode-LabReset-$timestamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
Write-Host "Backup root: $backupRoot"

$inventory = Get-BeautyFontInventory
Uninstall-VSCode
Clear-VSCodeActivePaths -BackupRoot $backupRoot
Remove-BeautyFontFiles -Inventory $inventory -BackupRoot $backupRoot
Remove-BeautyFontRegistryValues -Inventory $inventory
Send-FontChangeBroadcast
Show-ResetVerification -Inventory $inventory

Write-Host ""
Write-Ok "Reset complete."
