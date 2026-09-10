Set-StrictMode -Version Latest

$script:DefaultMaxHistory = 50
$script:DefaultMaxContentLength = 10000

function Get-ClipboardHistoryPath {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $env:LOCALAPPDATA 'clipboard-history\history.json'
    }
    return $Path
}

function New-ClipboardHistoryItem {
    param(
        [Parameter(Mandatory = $true)][string] $Content,
        [datetime] $Timestamp = (Get-Date),
        [int] $UseCount = 1
    )

    [pscustomobject]@{
        content    = $Content
        createdAt  = $Timestamp.ToString('o')
        lastUsedAt = $Timestamp.ToString('o')
        useCount   = $UseCount
    }
}

function Get-ClipboardHistory {
    param([string] $Path)

    $Path = Get-ClipboardHistoryPath $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        Save-ClipboardHistory -Items @() -Path $Path
        return @()
    }

    try {
        $json = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw 'The history file is empty.'
        }
        $items = @($json | ConvertFrom-Json)
        foreach ($item in $items) {
            if ($null -eq $item.content -or $null -eq $item.createdAt -or $null -eq $item.lastUsedAt -or $null -eq $item.useCount) {
                throw 'The history file has an invalid item.'
            }
        }
        return @($items | Sort-Object { [datetime]$_.lastUsedAt } -Descending)
    }
    catch {
        $backupPath = '{0}.corrupt-{1}' -f $Path, (Get-Date -Format 'yyyyMMddHHmmssfff')
        try {
            Move-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
            Write-Warning "Invalid history JSON was backed up to: $backupPath"
        }
        catch {
            Write-Warning "Could not back up invalid history JSON: $($_.Exception.Message)"
        }
        Save-ClipboardHistory -Items @() -Path $Path
        return @()
    }
}

function Save-ClipboardHistory {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Items,
        [string] $Path
    )

    $Path = Get-ClipboardHistoryPath $Path
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if ($Items.Count -eq 0) {
        $json = '[]'
    }
    else {
        $json = @($Items | Sort-Object { [datetime]$_.lastUsedAt } -Descending) | ConvertTo-Json -Depth 3
    }
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Add-ClipboardHistoryItem {
    param(
        [Parameter(Mandatory = $true)][string] $Content,
        [string] $Path,
        [ValidateRange(1, 2147483647)][int] $MaxHistory = $script:DefaultMaxHistory,
        [ValidateRange(1, 2147483647)][int] $MaxContentLength = $script:DefaultMaxContentLength
    )

    if ([string]::IsNullOrWhiteSpace($Content) -or $Content.Length -gt $MaxContentLength) {
        return $false
    }

    $items = @(Get-ClipboardHistory -Path $Path)
    $now = Get-Date
    $existing = @($items | Where-Object { $_.content -ceq $Content } | Select-Object -First 1)
    if ($existing.Count -gt 0) {
        $item = $existing[0]
        $item.lastUsedAt = $now.ToString('o')
        $item.useCount = [int]$item.useCount + 1
    }
    else {
        $items += New-ClipboardHistoryItem -Content $Content -Timestamp $now
    }

    $items = @($items | Sort-Object { [datetime]$_.lastUsedAt } -Descending | Select-Object -First $MaxHistory)
    Save-ClipboardHistory -Items $items -Path $Path
    return $true
}

function Use-ClipboardHistoryItem {
    param(
        [Parameter(Mandatory = $true)][string] $Content,
        [string] $Path,
        [ValidateRange(1, 2147483647)][int] $MaxHistory = $script:DefaultMaxHistory
    )

    $items = @(Get-ClipboardHistory -Path $Path)
    $matches = @($items | Where-Object { $_.content -ceq $Content } | Select-Object -First 1)
    if ($matches.Count -eq 0) {
        return $false
    }

    $matches[0].lastUsedAt = (Get-Date).ToString('o')
    $matches[0].useCount = [int]$matches[0].useCount + 1
    $items = @($items | Sort-Object { [datetime]$_.lastUsedAt } -Descending | Select-Object -First $MaxHistory)
    Save-ClipboardHistory -Items $items -Path $Path
    return $true
}

function Get-ClipboardHistoryPreview {
    param(
        [Parameter(Mandatory = $true)][string] $Content,
        [ValidateRange(1, 2147483647)][int] $Length = 100
    )

    $preview = $Content -replace '[\r\n]+', ' '
    if ($preview.Length -gt $Length) {
        return $preview.Substring(0, $Length - 3) + '...'
    }
    return $preview
}

function Show-ClipboardHistoryPicker {
    [CmdletBinding()]
    param(
        [string] $Path,
        [ValidateRange(1, 2147483647)][int] $MaxHistory = 50
    )

    $items = @(Get-ClipboardHistory -Path $Path)
    if ($items.Count -eq 0) {
        return $false
    }

    $displayItems = foreach ($item in $items) {
        [pscustomobject]@{
            LastUsed = ([datetime]$item.lastUsedAt).ToString('yyyy/MM/dd HH:mm')
            Count    = [int]$item.useCount
            Preview  = Get-ClipboardHistoryPreview -Content ([string]$item.content)
            Content  = [string]$item.content
        }
    }

    if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        throw 'Out-GridView is unavailable. Start clipboard-select.ps1 from a visible PowerShell window instead.'
    }

    $selectedDisplay = $displayItems | Select-Object LastUsed, Count, Preview | Out-GridView -Title 'Clipboard history' -PassThru
    if ($null -eq $selectedDisplay) {
        return $false
    }

    $selected = $displayItems | Where-Object {
        $_.LastUsed -eq $selectedDisplay.LastUsed -and $_.Count -eq $selectedDisplay.Count -and $_.Preview -eq $selectedDisplay.Preview
    } | Select-Object -First 1

    if ($null -eq $selected) {
        return $false
    }

    Set-Clipboard -Value $selected.Content
    Use-ClipboardHistoryItem -Content $selected.Content -Path $Path -MaxHistory $MaxHistory | Out-Null
    return $true
}

Export-ModuleMember -Function Get-ClipboardHistoryPath, Get-ClipboardHistory, Save-ClipboardHistory, Add-ClipboardHistoryItem, Use-ClipboardHistoryItem, Get-ClipboardHistoryPreview, Show-ClipboardHistoryPicker
