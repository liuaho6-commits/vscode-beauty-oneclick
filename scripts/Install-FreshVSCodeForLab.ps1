$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$url = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"
$installer = Join-Path $env:TEMP "VSCodeUserSetup-x64-latest.exe"

Write-Output "DOWNLOAD $url"
Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

$item = Get-Item -LiteralPath $installer
Write-Output "INSTALLER=$installer"
Write-Output "SIZE=$($item.Length)"

$args = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath"
Write-Output "RUN installer"
$process = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
Write-Output "INSTALL_EXIT=$($process.ExitCode)"

Start-Sleep -Seconds 3

$codeExe = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe"
if (-not (Test-Path -LiteralPath $codeExe)) {
    throw "Code.exe not found after install: $codeExe"
}

Write-Output "CODE_EXE=$codeExe"
$codeCli = Join-Path (Split-Path -Parent $codeExe) "bin\code.cmd"
if (Test-Path -LiteralPath $codeCli) {
    & $codeCli --version
}
else {
    Write-Warning "code.cmd was not found, so version output was skipped."
}

Write-Output "--- FRESH STATE ---"
$rows = foreach ($path in @(
    (Join-Path $env:APPDATA "Code"),
    (Join-Path $env:USERPROFILE ".vscode"),
    (Join-Path $env:USERPROFILE ".vscode\extensions")
)) {
    [pscustomobject]@{
        Path = $path
        Exists = Test-Path -LiteralPath $path
    }
}
$rows | Format-Table -AutoSize
