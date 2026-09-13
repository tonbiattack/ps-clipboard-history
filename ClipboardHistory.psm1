Set-StrictMode -Version Latest

# Windows Forms と Drawing は、クリップボード画像とコピー元ウィンドウを扱うために必要です。
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 値は関数の既定値に集約し、呼び出し側が省略しても保存量を一定に保ちます。
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

    # 保存先を指定しない通常利用では、ユーザー単位の LocalAppData 配下に保存します。
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $env:LOCALAPPDATA 'clipboard-history\history.json'
    }
    return $Path
}

function Get-ClipboardImageDirectory {
    param([string] $Path)

    $historyPath = Get-ClipboardHistoryPath $Path
    return Join-Path (Split-Path -Parent $historyPath) 'images'
}

function New-ClipboardHistoryItem {
    param(
        [Parameter(Mandatory = $true)][string] $Content,
        [datetime] $Timestamp = (Get-Date),
        [psobject] $Source
    )

    [pscustomobject]@{
        type               = 'text'
        content           = $Content
        createdAt         = $Timestamp.ToString('o')
        lastUsedAt        = $Timestamp.ToString('o')
        sourceApp         = if ($null -ne $Source) { [string]$Source.AppName } else { $null }
        sourceWindowTitle = if ($null -ne $Source) { [string]$Source.WindowTitle } else { $null }
    }
}

function New-ClipboardImageHistoryItem {
    param(
        [Parameter(Mandatory = $true)][string] $ImagePath,
        [datetime] $Timestamp = (Get-Date),
        [psobject] $Source
    )

    [pscustomobject]@{
        type               = 'image'
        content           = $null
        imagePath         = $ImagePath
        createdAt         = $Timestamp.ToString('o')
        lastUsedAt        = $Timestamp.ToString('o')
        sourceApp         = if ($null -ne $Source) { [string]$Source.AppName } else { $null }
        sourceWindowTitle = if ($null -ne $Source) { [string]$Source.WindowTitle } else { $null }
    }
}

function Get-ClipboardImageFingerprint {
    param([Parameter(Mandatory = $true)][System.Drawing.Image] $Image)

    # 画像そのものではなく PNG 化したバイト列をハッシュ化し、同じ画像の重複記録を防ぎます。
    $stream = [System.IO.MemoryStream]::new()
    try {
        $Image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $hash = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($hash.ComputeHash($stream.ToArray()))).Replace('-', '')
        }
        finally {
            $hash.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-ClipboardSource {
    # コピー操作時に前面だったウィンドウを取得し、履歴の補助情報としてだけ保存します。
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

        return [pscustomobject]@{
            AppName     = $process.ProcessName
            WindowTitle = $titleBuffer.ToString()
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
        # JSON は常に UTF-8 として読みます。PowerShell の既定エンコーディングには依存しません。
        $json = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw 'The history file is empty.'
        }
        # Windows PowerShell 5.1 は JSON 配列を Object[] 一つとして出力します。
        # 平坦化して、複数件でも並び替えと更新が正常に動くようにします。
        $items = @($json | ConvertFrom-Json | ForEach-Object { $_ })
        foreach ($item in $items) {
            if ($null -eq $item.createdAt -or $null -eq $item.lastUsedAt) {
                throw 'The history file has an invalid item.'
            }
            if ($null -eq $item.PSObject.Properties['type']) {
                $item | Add-Member -NotePropertyName type -NotePropertyValue 'text'
            }
            if ($item.type -eq 'text' -and $null -eq $item.content) {
                throw 'The history file has an invalid text item.'
            }
            if ($item.type -eq 'image' -and [string]::IsNullOrWhiteSpace([string]$item.imagePath)) {
                throw 'The history file has an invalid image item.'
            }
            # 旧版で保存された不要なプロパティは、次回保存時に互換的に取り除きます。
            [void]$item.PSObject.Properties.Remove('useCount')
            [void]$item.PSObject.Properties.Remove('sourceProcessPath')
            foreach ($propertyName in @('sourceApp', 'sourceWindowTitle')) {
                if ($null -eq $item.PSObject.Properties[$propertyName]) {
                    $item | Add-Member -NotePropertyName $propertyName -NotePropertyValue $null
                }
                if ($item.type -eq 'text' -and $null -eq $item.PSObject.Properties['imagePath']) {
                    $item | Add-Member -NotePropertyName imagePath -NotePropertyValue $null
                }
            }
        }
        return @($items | Sort-Object { [datetime]$_.lastUsedAt } -Descending)
    }
    catch {
        # 壊れた履歴を上書きしないため、まず退避してから空の履歴を作成します。
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

    # 空配列も JSON として明示的に保存し、次回読み込み時の形式を一定にします。
    if ($Items.Count -eq 0) {
        $json = '[]'
    }
    else {
        $json = @($Items | Sort-Object { [datetime]$_.lastUsedAt } -Descending) | ConvertTo-Json -Depth 3
    }
    # データファイルは BOM なし UTF-8 に固定し、日本語を含むクリップボード内容も安全に保持します。
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

    # 空白だけ、または上限超過の文字列は履歴へ保存しません。
    if ([string]::IsNullOrWhiteSpace($Content) -or $Content.Length -gt $MaxContentLength) {
        return $false
    }

    $items = @(Get-ClipboardHistory -Path $Path)
    $now = Get-Date
    $existing = @($items | Where-Object { $_.content -ceq $Content } | Select-Object -First 1)
    if ($existing.Count -gt 0) {
        # 同じ文字列は追加せず、最終利用時刻を更新して MRU の先頭へ移動させます。
        $item = $existing[0]
        $item.lastUsedAt = $now.ToString('o')
        if ($null -ne $Source) {
            $item.sourceApp = [string]$Source.AppName
            $item.sourceWindowTitle = [string]$Source.WindowTitle
        }
    }
    else {
        $items += New-ClipboardHistoryItem -Content $Content -Timestamp $now -Source $Source
    }

    $items = @($items | Sort-Object { [datetime]$_.lastUsedAt } -Descending | Select-Object -First $MaxHistory)
    Save-ClipboardHistory -Items $items -Path $Path
    return $true
}

function Add-ClipboardImageHistoryItem {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Image] $Image,
        [string] $Path,
        [ValidateRange(1, 2147483647)][int] $MaxHistory = $script:DefaultMaxHistory,
        [psobject] $Source
    )

    $historyPath = Get-ClipboardHistoryPath $Path
    $imageDirectory = Get-ClipboardImageDirectory -Path $historyPath
    if (-not (Test-Path -LiteralPath $imageDirectory)) {
        New-Item -ItemType Directory -Path $imageDirectory -Force | Out-Null
    }

    $imageFileName = '{0}.png' -f [guid]::NewGuid().ToString('N')
    $imagePath = Join-Path $imageDirectory $imageFileName
    try {
        $Image.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $items = @(Get-ClipboardHistory -Path $historyPath)
        $now = Get-Date
        $allItems = @($items + (New-ClipboardImageHistoryItem -ImagePath $imagePath -Timestamp $now -Source $Source))
        $items = @($allItems | Sort-Object { [datetime]$_.lastUsedAt } -Descending | Select-Object -First $MaxHistory)
        # 履歴上限から外れた画像の実体も削除し、画像フォルダーだけが増え続けないようにします。
        foreach ($removedItem in @($allItems | Where-Object { $items -notcontains $_ -and $_.type -eq 'image' })) {
            if (Test-Path -LiteralPath $removedItem.imagePath) {
                Remove-Item -LiteralPath $removedItem.imagePath -Force
            }
        }
        Save-ClipboardHistory -Items $items -Path $historyPath
        return $true
    }
    catch {
        if (Test-Path -LiteralPath $imagePath) {
            Remove-Item -LiteralPath $imagePath -Force
        }
        throw
    }
}

function Use-ClipboardHistoryItem {
    param(
        [string] $Content,
        [psobject] $Item,
        [string] $Path,
        [ValidateRange(1, 2147483647)][int] $MaxHistory = $script:DefaultMaxHistory
    )

    $items = @(Get-ClipboardHistory -Path $Path)
    if ($null -eq $Item) {
        $matches = @($items | Where-Object { $_.type -eq 'text' -and $_.content -ceq $Content } | Select-Object -First 1)
    }
    else {
        $matches = @($items | Where-Object {
            if ($Item.type -eq 'image') { $_.type -eq 'image' -and $_.imagePath -eq $Item.imagePath }
            else { $_.type -eq 'text' -and $_.content -ceq $Item.content }
        } | Select-Object -First 1)
    }
    if ($matches.Count -eq 0) {
        return $false
    }

    # 再利用も MRU とみなし、コピーした項目を次回一覧の先頭にします。
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

    # 一覧の可読性を保つため改行を空白にし、保存済みの全文は変更しません。
    $preview = $Content -replace '[\r\n]+', ' '
    if ($preview.Length -gt $Length) {
        return $preview.Substring(0, $Length - 3) + '...'
    }
    return $preview
}

function Get-ClipboardHistoryItemLabel {
    param([Parameter(Mandatory = $true)][psobject] $Item)

    if ($Item.type -eq 'image') {
        return '[Image]'
    }
    return Get-ClipboardHistoryPreview -Content ([string]$Item.content)
}

Export-ModuleMember -Function Get-ClipboardHistoryPath, Get-ClipboardImageDirectory, Get-ClipboardHistory, Save-ClipboardHistory, Add-ClipboardHistoryItem, Add-ClipboardImageHistoryItem, Use-ClipboardHistoryItem, Get-ClipboardHistoryPreview, Get-ClipboardHistoryItemLabel, Get-ClipboardImageFingerprint, Get-ClipboardSource
