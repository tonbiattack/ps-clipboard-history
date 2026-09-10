[CmdletBinding()]
param()

Set-StrictMode -Version Latest

$installerPath = Join-Path $PSScriptRoot 'install-shortcut.ps1'
$watcherLauncherPath = Join-Path $PSScriptRoot 'clipboard-watch.vbs'

& $installerPath -Force

$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
if (-not (Test-Path -LiteralPath $wscript -PathType Leaf)) {
    $wscript = (Get-Command wscript.exe -ErrorAction Stop).Source
}

Start-Process -FilePath $wscript -ArgumentList ('"{0}"' -f $watcherLauncherPath)
Write-Host 'Setup complete. Clipboard History is running in the notification area.'
