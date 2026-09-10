[CmdletBinding()]
param(
    [string] $HistoryPath,
    [ValidateRange(1, 2147483647)][int] $MaxHistory = 50
)

Import-Module (Join-Path $PSScriptRoot 'ClipboardHistory.psm1') -Force

if (-not (Show-ClipboardHistoryPicker -Path $HistoryPath -MaxHistory $MaxHistory)) {
    Write-Host 'Clipboard history is empty or selection was cancelled.'
}
