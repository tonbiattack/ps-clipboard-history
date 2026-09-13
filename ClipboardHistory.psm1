Set-StrictMode -Version Latest

$script:DefaultMaxHistory = 500
$script:DefaultMaxContentLength = 10000

if (-not ('ClipboardHistory.NativeMethods' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace ClipboardHistory {
    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    }
}
'@
}

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
        [psobject] $Source
    )

    [pscustomobject]@{
        content           = $Content
        createdAt         = $Timestamp.ToString('o')
        lastUsedAt        = $Timestamp.ToString('o')
        sourceApp         = if ($null -ne $Source) { [string]$Source.AppName } else { $null }
        sourceWindowTitle = if ($null -ne $Source) { [string]$Source.WindowTitle } else { $null }
        sourceProcessPath = if ($null -ne $Source) { [string]$Source.ProcessPath } else { $null }
    }
}

function Get-ClipboardSource {
    $windowHandle = [ClipboardHistory.NativeMethods]::GetForegroundWindow()
    if ($windowHandle -eq [IntPtr]::Zero) {
        return $null
    }

    $processId = [uint32]0
    [void][ClipboardHistory.NativeMethods]::GetWindowThreadProcessId($windowHandle, [ref]$processId)
    if ($processId -eq 0) {
        return $null
    }

    try {
        $process = [System.Diagnostics.Process]::GetProcessById([int]$processId)
        $titleBuffer = [System.Text.StringBuilder]::new(1024)
        [void][ClipboardHistory.NativeMethods]::GetWindowText($windowHandle, $titleBuffer, $titleBuffer.Capacity)
        $processPath = $null
        try {
            $processPath = $process.MainModule.FileName
        }
        catch {
            # Some protected processes do not expose their executable path.
        }

        return [pscustomobject]@{
            AppName     = $process.ProcessName
            WindowTitle = $titleBuffer.ToString()
            ProcessPath = $processPath
        }
    }
    catch {
        Write-Warning "Could not identify the clipboard source application: $($_.Exception.Message)"
        return $null
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
        # Windows PowerShell 5.1 emits a JSON array as one Object[] pipeline value.
        # Flatten it so sorting and history updates work for more than one item.
        $items = @($json | ConvertFrom-Json | ForEach-Object { $_ })
        foreach ($item in $items) {
            if ($null -eq $item.content -or $null -eq $item.createdAt -or $null -eq $item.lastUsedAt) {
                throw 'The history file has an invalid item.'
            }
            # Remove the no-longer-used counter from histories written by older versions.
            [void]$item.PSObject.Properties.Remove('useCount')
            foreach ($propertyName in @('sourceApp', 'sourceWindowTitle', 'sourceProcessPath')) {
                if ($null -eq $item.PSObject.Properties[$propertyName]) {
                    $item | Add-Member -NotePropertyName $propertyName -NotePropertyValue $null
                }
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
        [ValidateRange(1, 2147483647)][int] $MaxContentLength = $script:DefaultMaxContentLength,
        [psobject] $Source
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
        if ($null -ne $Source) {
            $item.sourceApp = [string]$Source.AppName
            $item.sourceWindowTitle = [string]$Source.WindowTitle
            $item.sourceProcessPath = [string]$Source.ProcessPath
        }
    }
    else {
        $items += New-ClipboardHistoryItem -Content $Content -Timestamp $now -Source $Source
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
        [ValidateRange(1, 2147483647)][int] $MaxHistory = $script:DefaultMaxHistory
    )

    $items = @(Get-ClipboardHistory -Path $Path)
    if ($items.Count -eq 0) {
        return $false
    }

    $displayItems = foreach ($item in $items) {
        [pscustomobject]@{
            LastUsed = ([datetime]$item.lastUsedAt).ToString('yyyy/MM/dd HH:mm')
            Preview  = Get-ClipboardHistoryPreview -Content ([string]$item.content)
            Content  = [string]$item.content
        }
    }

    if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        throw 'Out-GridView is unavailable. Start clipboard-select.ps1 from a visible PowerShell window instead.'
    }

    $selectedDisplay = $displayItems | Select-Object LastUsed, Preview | Out-GridView -Title 'Clipboard history' -PassThru
    if ($null -eq $selectedDisplay) {
        return $false
    }

    $selected = $displayItems | Where-Object {
        $_.LastUsed -eq $selectedDisplay.LastUsed -and $_.Preview -eq $selectedDisplay.Preview
    } | Select-Object -First 1

    if ($null -eq $selected) {
        return $false
    }

    Set-Clipboard -Value $selected.Content
    Use-ClipboardHistoryItem -Content $selected.Content -Path $Path -MaxHistory $MaxHistory | Out-Null
    return $true
}

Export-ModuleMember -Function Get-ClipboardHistoryPath, Get-ClipboardHistory, Save-ClipboardHistory, Add-ClipboardHistoryItem, Use-ClipboardHistoryItem, Get-ClipboardHistoryPreview, Get-ClipboardSource, Show-ClipboardHistoryPicker
