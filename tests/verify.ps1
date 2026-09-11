[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-That {
    param(
        [Parameter(Mandatory = $true)][bool] $Condition,
        [Parameter(Mandatory = $true)][string] $Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'ClipboardHistory.psm1'
$watcherPath = Join-Path $repoRoot 'clipboard-watch.ps1'
$installerPath = Join-Path $repoRoot 'install-shortcut.ps1'
$testRoot = Join-Path $env:TEMP ('ps-clipboard-history-verify-' + [guid]::NewGuid().ToString())
$historyPath = Join-Path $testRoot 'history.json'

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
Import-Module $modulePath -Force

$moduleSource = Get-Content -Raw -LiteralPath $modulePath
Assert-That ($moduleSource -match '\$script:DefaultMaxHistory = 500') 'default history retention is 500'

Add-ClipboardHistoryItem -Content 'first' -Path $historyPath | Out-Null
Start-Sleep -Milliseconds 5
Add-ClipboardHistoryItem -Content 'second' -Path $historyPath | Out-Null
Start-Sleep -Milliseconds 5
Add-ClipboardHistoryItem -Content 'first' -Path $historyPath | Out-Null

$items = @(Get-ClipboardHistory -Path $historyPath)
Assert-That ($items.Count -eq 2) 'deduplication keeps two distinct entries'
Assert-That ($items[0].content -eq 'first') 'reused content moves to the top'
Assert-That (-not ($items | Where-Object { $_.PSObject.Properties.Name -contains 'useCount' })) 'history objects have no useCount'

$legacyPath = Join-Path $testRoot 'legacy.json'
[System.IO.File]::WriteAllText($legacyPath, '[{"content":"legacy","createdAt":"2026-01-01T00:00:00.0000000+00:00","lastUsedAt":"2026-01-01T00:00:00.0000000+00:00","useCount":9}]', [System.Text.UTF8Encoding]::new($false))
Use-ClipboardHistoryItem -Content 'legacy' -Path $legacyPath | Out-Null
Assert-That (-not ((Get-Content -Raw -LiteralPath $legacyPath) -match 'useCount')) 'legacy useCount is removed when history is updated'

Add-ClipboardHistoryItem -Content 'third' -Path $historyPath -MaxHistory 2 | Out-Null
Assert-That (@(Get-ClipboardHistory -Path $historyPath).Count -eq 2) 'max history is enforced'

$watcherSource = Get-Content -Raw -LiteralPath $watcherPath
Assert-That ($watcherSource -match 'SearchBox') 'search box state exists'
Assert-That ($watcherSource -match 'Add_TextChanged') 'search refresh handler exists'
Assert-That ($watcherSource -match 'OrdinalIgnoreCase') 'search is case-insensitive'
Assert-That ($watcherSource -match 'IndexOf\(\$query') 'search filters clipboard content'
Assert-That ($watcherSource -match 'Keys\]::F') 'Ctrl+F focuses the search box'
Assert-That ($watcherSource -match '\$searchBox\.Visible = \$false') 'search box is hidden until requested'
Assert-That ($watcherSource -match 'Add_CellClick') 'mouse row-click copy handler exists'
Assert-That ($watcherSource -match 'Add_KeyDown') 'keyboard handler exists'
Assert-That ($watcherSource -match 'Keys\]::Enter') 'Enter copies the selected row'
Assert-That ($watcherSource -match "Columns\.Add\('Number', 'No\.'") 'number column is present'
Assert-That ($watcherSource -match 'NumberPrefix') 'number input selects a history row'
Assert-That ($watcherSource -notmatch 'Add_SelectionChanged') 'arrow-key selection does not copy'
Assert-That ($watcherSource -notmatch '\$state\.HistoryForm\.Hide\(\)') 'history window remains open after copying a row'
Assert-That ($watcherSource -notmatch 'RegisterHotKey') 'global hotkey registration is absent'
Assert-That ($watcherSource -notmatch 'ClipboardHistoryHotkeyForm') 'hotkey host form is absent'
Assert-That ($watcherSource -match 'ApplicationContext') 'tray application uses an application context without a hotkey form'
Assert-That ($watcherSource -match "Font\]::new\('Segoe UI', 12") 'history UI uses a readable 12pt font'
Assert-That ($watcherSource -match 'RowTemplate.Height = 32') 'history UI uses readable row height'
Assert-That ($watcherSource -notmatch "Columns\.Add\('Count'") 'count column is absent'

$shortcutDirectory = Join-Path $testRoot 'desktop'
$watcherShortcutDirectory = Join-Path $testRoot 'startup'
& $installerPath -ShortcutDirectory $shortcutDirectory -WatcherShortcutDirectory $watcherShortcutDirectory
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $shortcutDirectory 'Clipboard History.lnk'))
Assert-That ($shortcut.TargetPath -match 'wscript\.exe$') 'desktop shortcut uses wscript'
Assert-That ($shortcut.Arguments -match 'clipboard-watch\.vbs') 'desktop shortcut opens the resident app'

Write-Host 'All verification checks passed.'
