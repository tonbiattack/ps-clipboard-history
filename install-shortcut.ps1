[CmdletBinding()]
param(
    [string] $ShortcutDirectory,
    [string] $WatcherShortcutDirectory,
    [switch] $Force
)

Set-StrictMode -Version Latest

$watcherLauncherPath = Join-Path $PSScriptRoot 'clipboard-watch.vbs'
if (-not (Test-Path -LiteralPath $watcherLauncherPath -PathType Leaf)) {
    throw "clipboard-watch.vbs was not found: $watcherLauncherPath"
}

if ([string]::IsNullOrWhiteSpace($ShortcutDirectory)) {
    $ShortcutDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
}

if (-not (Test-Path -LiteralPath $ShortcutDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($WatcherShortcutDirectory)) {
    $WatcherShortcutDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
}

if (-not (Test-Path -LiteralPath $WatcherShortcutDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $WatcherShortcutDirectory -Force | Out-Null
}

$shortcutPath = Join-Path $ShortcutDirectory 'Clipboard History.lnk'
if ((Test-Path -LiteralPath $shortcutPath) -and -not $Force) {
    throw "The shortcut already exists: $shortcutPath. Use -Force to replace it."
}

$watcherShortcutPath = Join-Path $WatcherShortcutDirectory 'Clipboard History Watcher.lnk'
if ((Test-Path -LiteralPath $watcherShortcutPath) -and -not $Force) {
    throw "The watcher shortcut already exists: $watcherShortcutPath. Use -Force to replace it."
}

$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    $windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
}

$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
if (-not (Test-Path -LiteralPath $wscript -PathType Leaf)) {
    $wscript = (Get-Command wscript.exe -ErrorAction Stop).Source
}

$trayIconPath = Join-Path $PSScriptRoot 'assets\tray-icon.ico'
$iconLocation = if (Test-Path -LiteralPath $trayIconPath -PathType Leaf) { "$trayIconPath,0" } else { "$windowsPowerShell,0" }

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $wscript
$shortcut.Arguments = '"{0}"' -f $watcherLauncherPath
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Open the Clipboard History resident app'
$shortcut.IconLocation = $iconLocation
$shortcut.Save()

$watcherShortcut = $shell.CreateShortcut($watcherShortcutPath)
$watcherShortcut.TargetPath = $wscript
$watcherShortcut.Arguments = '"{0}"' -f $watcherLauncherPath
$watcherShortcut.WorkingDirectory = $PSScriptRoot
$watcherShortcut.Description = 'Run ps-clipboard-history watcher without a console window'
$watcherShortcut.IconLocation = $iconLocation
$watcherShortcut.Save()

Write-Host "Created shortcut: $shortcutPath"
Write-Host "Created startup watcher: $watcherShortcutPath"
