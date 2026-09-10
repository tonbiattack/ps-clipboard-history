[CmdletBinding()]
param(
    [ValidateSet('Desktop', 'StartMenu')]
    [string] $Destination = 'Desktop',
    [string] $ShortcutDirectory,
    [switch] $Force
)

Set-StrictMode -Version Latest

$selectorPath = Join-Path $PSScriptRoot 'clipboard-select.ps1'
if (-not (Test-Path -LiteralPath $selectorPath -PathType Leaf)) {
    throw "clipboard-select.ps1 was not found: $selectorPath"
}

if ([string]::IsNullOrWhiteSpace($ShortcutDirectory)) {
    if ($Destination -eq 'Desktop') {
        $ShortcutDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    }
    else {
        $ShortcutDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    }
}

if (-not (Test-Path -LiteralPath $ShortcutDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
}

$shortcutPath = Join-Path $ShortcutDirectory 'Clipboard History.lnk'
if ((Test-Path -LiteralPath $shortcutPath) -and -not $Force) {
    throw "The shortcut already exists: $shortcutPath. Use -Force to replace it."
}

$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    $windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $windowsPowerShell
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $selectorPath
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Open ps-clipboard-history'
$shortcut.Hotkey = 'CTRL+ALT+V'
$shortcut.IconLocation = "$windowsPowerShell,0"
$shortcut.Save()

Write-Host "Created shortcut: $shortcutPath"
Write-Host 'Shortcut key: Ctrl + Alt + V (change it in shortcut properties if needed).'
