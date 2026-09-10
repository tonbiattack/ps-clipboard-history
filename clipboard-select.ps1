[CmdletBinding()]
param(
    [string] $HistoryPath,
    [ValidateRange(1, 2147483647)][int] $MaxHistory = 50
)

Import-Module (Join-Path $PSScriptRoot 'ClipboardHistory.psm1') -Force

$items = @(Get-ClipboardHistory -Path $HistoryPath)
if ($items.Count -eq 0) {
    Write-Host 'Clipboard history is empty.'
    return
}

$displayItems = foreach ($item in $items) {
    [pscustomobject]@{
        LastUsed = ([datetime]$item.lastUsedAt).ToString('yyyy/MM/dd HH:mm')
        Count    = [int]$item.useCount
        Preview  = Get-ClipboardHistoryPreview -Content ([string]$item.content)
        Content  = [string]$item.content
    }
}

if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
    $selectedDisplay = $displayItems | Select-Object LastUsed, Count, Preview | Out-GridView -Title 'Clipboard history' -PassThru
    if ($null -ne $selectedDisplay) {
        $selected = $displayItems | Where-Object {
            $_.LastUsed -eq $selectedDisplay.LastUsed -and $_.Count -eq $selectedDisplay.Count -and $_.Preview -eq $selectedDisplay.Preview
        } | Select-Object -First 1
    }
}
else {
    Write-Host 'Out-GridView is unavailable. Select an item by number:'
    for ($index = 0; $index -lt $displayItems.Count; $index++) {
        Write-Host ('[{0}] {1}  {2}  {3}' -f ($index + 1), $displayItems[$index].LastUsed, $displayItems[$index].Count, $displayItems[$index].Preview)
    }
    $answer = Read-Host 'Number (blank to cancel)'
    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $displayItems.Count) {
        $selected = $displayItems[$number - 1]
    }
}

if ($null -ne $selected) {
    Set-Clipboard -Value $selected.Content
    Use-ClipboardHistoryItem -Content $selected.Content -Path $HistoryPath -MaxHistory $MaxHistory | Out-Null
    Write-Host 'Selected item copied to the clipboard.'
}
