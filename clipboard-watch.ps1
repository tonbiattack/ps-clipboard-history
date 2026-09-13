[CmdletBinding()]
param(
    [string] $HistoryPath,
    [ValidateRange(50, 60000)][int] $IntervalMilliseconds = 500,
    [ValidateRange(1, 2147483647)][int] $MaxHistory = 500,
    [ValidateRange(1, 2147483647)][int] $MaxContentLength = 10000,
    [switch] $RunOnce,
    [string] $MutexName = 'Local\PsClipboardHistoryWatch',
    [string] $LogPath,
    [switch] $EnableDebugLog
)

Import-Module (Join-Path $PSScriptRoot 'ClipboardHistory.psm1') -Force

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $env:LOCALAPPDATA 'clipboard-history\watch.log'
}
$logDirectory = Split-Path -Parent $LogPath
if (-not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

function Write-WatchLog {
    param(
        [Parameter(Mandatory = $true)][string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string] $Level = 'INFO'
    )

    if (-not $EnableDebugLog -and $Level -eq 'INFO') {
        return
    }
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never crash the watcher.
    }
}

$mutex = [System.Threading.Mutex]::new($false, $MutexName)
if (-not $mutex.WaitOne(0, $false)) {
    Write-Host 'clipboard-watch.ps1 is already running.'
    Write-WatchLog -Level WARN -Message 'Startup aborted: another instance is already running.'
    exit 1
}

Write-WatchLog -Message ('Starting clipboard-watch.ps1 (PID {0}).' -f $PID)

try {
    $applicationContext = $null
    $notifyIcon = $null
    $menu = $null
    $timer = $null

    $state = [pscustomobject]@{
        PreviousContent = $null
        PreviousImageFingerprint = $null
        IsRefreshing    = $false
        HistoryForm     = $null
        Grid            = $null
        SearchBox       = $null
        Status          = $null
        CopyHistoryRow  = $null
        NumberPrefix    = ''
        NumberInputAt   = [datetime]::MinValue
    }

    $refreshHistoryGrid = {
        if ($null -eq $state.Grid -or $state.HistoryForm.IsDisposed) {
            return
        }
        $state.NumberPrefix = ''

        $selectedContent = $null
        if ($state.Grid.SelectedRows.Count -gt 0) {
            $selectedContent = [string]$state.Grid.SelectedRows[0].Tag
        }

        $query = ''
        if ($null -ne $state.SearchBox) {
            $query = [string]$state.SearchBox.Text
        }

        $state.IsRefreshing = $true
        try {
            $state.Grid.Rows.Clear()
            $items = @(Get-ClipboardHistory -Path $HistoryPath)
            if (-not [string]::IsNullOrWhiteSpace($query)) {
                $items = @($items | Where-Object {
                    $_.type -eq 'image' -or ([string]$_.content).IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                })
            }

            $selectedRow = $null
            foreach ($item in $items) {
                $displayNumber = $state.Grid.Rows.Count + 1
                $rowIndex = $state.Grid.Rows.Add(
                    $displayNumber,
                    ([datetime]$item.lastUsedAt).ToString('yyyy/MM/dd HH:mm:ss'),
                    (Get-ClipboardHistoryItemLabel -Item $item),
                    $(if ([string]::IsNullOrWhiteSpace([string]$item.sourceApp)) {
                        'Unknown'
                    }
                    else {
                        '{0} - {1}' -f $item.sourceApp, $item.sourceWindowTitle
                    })
                )
                $row = $state.Grid.Rows[$rowIndex]
                $row.Tag = $item
                if (($item.type -eq 'text' -and [string]$item.content -ceq $selectedContent) -or
                    ($item.type -eq 'image' -and '[Image]' -eq $selectedContent)) {
                    $selectedRow = $row
                }
            }

            if ($null -ne $selectedRow) {
                $selectedRow.Selected = $true
            }

            if ($null -ne $state.Status) {
                if ([string]::IsNullOrWhiteSpace($query)) {
                    $state.Status.Text = ('{0} item(s). Select a row to copy it.' -f $items.Count)
                }
                else {
                    $state.Status.Text = ('{0} item(s) matched "{1}".' -f $items.Count, $query)
                }
            }
        }
        finally {
            $state.IsRefreshing = $false
        }
    }

    $openHistory = {
        if ($null -ne $state.HistoryForm -and -not $state.HistoryForm.IsDisposed) {
            if ($state.HistoryForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
                $state.HistoryForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            }
            $state.HistoryForm.Show()
            $state.HistoryForm.Activate()
            $state.HistoryForm.BringToFront()
            if ($null -ne $state.SearchBox) {
                $state.SearchBox.Focus()
                $state.SearchBox.SelectAll()
            }
            return
        }

        $historyForm = [System.Windows.Forms.Form]::new()
        $historyForm.Text = 'Clipboard history'
        $historyForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $historyForm.Size = [System.Drawing.Size]::new(1100, 650)
        $historyForm.MinimumSize = [System.Drawing.Size]::new(760, 450)
        $historyForm.KeyPreview = $true

        $uiFont = [System.Drawing.Font]::new('Segoe UI', 12)
        $headerFont = [System.Drawing.Font]::new('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)

        $searchBox = [System.Windows.Forms.TextBox]::new()
        $searchBox.Dock = [System.Windows.Forms.DockStyle]::Top
        $searchBox.Font = $uiFont
        $searchBox.Height = 36
        $searchBox.Margin = [System.Windows.Forms.Padding]::new(8)
        $searchBox.Visible = $false

        $grid = [System.Windows.Forms.DataGridView]::new()
        $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
        $grid.ReadOnly = $true
        $grid.AllowUserToAddRows = $false
        $grid.AllowUserToDeleteRows = $false
        $grid.AllowUserToResizeRows = $false
        $grid.AutoGenerateColumns = $false
        $grid.MultiSelect = $false
        $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
        $grid.RowHeadersVisible = $false
        $grid.Font = $uiFont
        $grid.ColumnHeadersDefaultCellStyle.Font = $headerFont
        $grid.ColumnHeadersHeight = 36
        $grid.RowTemplate.Height = 32
        $grid.DefaultCellStyle.Padding = [System.Windows.Forms.Padding]::new(4, 2, 4, 2)

        [void]$grid.Columns.Add('Number', 'No.')
        [void]$grid.Columns.Add('LastUsed', 'Last used')
        [void]$grid.Columns.Add('Preview', 'Preview')
        [void]$grid.Columns.Add('Source', 'Copied from')
        $grid.Columns['Number'].Width = 56
        $grid.Columns['LastUsed'].Width = 150
        $grid.Columns['Source'].Width = 300
        $grid.Columns['Preview'].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill

        $status = [System.Windows.Forms.Label]::new()
        $status.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $status.Font = [System.Drawing.Font]::new('Segoe UI', 11)
        $status.Height = 34
        $status.Padding = [System.Windows.Forms.Padding]::new(10, 7, 10, 0)
        $status.Text = 'Type a number to select, then press Enter to copy. Ctrl+F searches.'

        $historyForm.Controls.Add($grid)
        $historyForm.Controls.Add($searchBox)
        $historyForm.Controls.Add($status)
        $state.HistoryForm = $historyForm
        $state.Grid = $grid
        $state.SearchBox = $searchBox
        $state.Status = $status

        $state.CopyHistoryRow = {
            param([int] $RowIndex)

            if ($state.IsRefreshing -or $RowIndex -lt 0) {
                return
            }

            $item = $state.Grid.Rows[$RowIndex].Tag
            if ($item.type -eq 'image') {
                $image = [System.Drawing.Image]::FromFile($item.imagePath)
                try { [System.Windows.Forms.Clipboard]::SetImage($image) } finally { $image.Dispose() }
                Use-ClipboardHistoryItem -Item $item -Path $HistoryPath -MaxHistory $MaxHistory | Out-Null
                $state.PreviousImageFingerprint = Get-ClipboardImageFingerprint -Image ([System.Windows.Forms.Clipboard]::GetImage())
            }
            else {
                $content = [string]$item.content
                Set-Clipboard -Value $content
                Use-ClipboardHistoryItem -Content $content -Path $HistoryPath -MaxHistory $MaxHistory | Out-Null
                $state.PreviousContent = $content
            }
            $state.NumberPrefix = ''
            & $refreshHistoryGrid
            $state.Status.Text = 'Copied to clipboard.'
        }

        $searchBox.Add_TextChanged({
            if (-not $state.IsRefreshing) {
                & $refreshHistoryGrid
            }
        })

        $searchBox.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Down -and $state.Grid.Rows.Count -gt 0) {
                $eventArgs.SuppressKeyPress = $true
                $state.Grid.Focus()
                $state.Grid.Rows[0].Selected = $true
            }
            elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                $eventArgs.SuppressKeyPress = $true
                $sender.Clear()
                $sender.Visible = $false
                $state.Grid.Focus()
            }
        })

        $historyForm.Add_KeyDown({
            param($sender, $eventArgs)

            if ($eventArgs.Control -and $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F) {
                $eventArgs.SuppressKeyPress = $true
                $state.SearchBox.Visible = $true
                $state.SearchBox.Focus()
                $state.SearchBox.SelectAll()
                return
            }

            if ($state.SearchBox.Focused) {
                return
            }

            $digit = $null
            $keyCode = [int]$eventArgs.KeyCode
            if ($keyCode -ge [int][System.Windows.Forms.Keys]::D0 -and $keyCode -le [int][System.Windows.Forms.Keys]::D9) {
                $digit = $keyCode - [int][System.Windows.Forms.Keys]::D0
            }
            elseif ($keyCode -ge [int][System.Windows.Forms.Keys]::NumPad0 -and $keyCode -le [int][System.Windows.Forms.Keys]::NumPad9) {
                $digit = $keyCode - [int][System.Windows.Forms.Keys]::NumPad0
            }

            if ($null -eq $digit) {
                if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                    $eventArgs.SuppressKeyPress = $true
                    $state.NumberPrefix = ''
                    $state.NumberInputAt = [datetime]::MinValue
                    $state.Status.Text = 'Number selection cleared.'
                }
                return
            }

            $eventArgs.SuppressKeyPress = $true
            if (((Get-Date) - $state.NumberInputAt).TotalMilliseconds -gt 1200) {
                $state.NumberPrefix = ''
            }
            $state.NumberInputAt = Get-Date
            $state.NumberPrefix += [string]$digit
            $selectedNumber = 0
            if (-not [int]::TryParse($state.NumberPrefix, [ref]$selectedNumber)) {
                $state.Status.Text = ('No. {0} was not found. Press Escape to clear it.' -f $state.NumberPrefix)
                return
            }

            $selectedIndex = $selectedNumber - 1
            if ($selectedIndex -ge 0 -and $selectedIndex -lt $state.Grid.Rows.Count) {
                $state.Grid.ClearSelection()
                $row = $state.Grid.Rows[$selectedIndex]
                $row.Selected = $true
                $state.Grid.CurrentCell = $row.Cells['Preview']
                $state.Grid.FirstDisplayedScrollingRowIndex = $selectedIndex
                $state.Status.Text = ('No. {0} selected. Press Enter to copy.' -f $state.NumberPrefix)
            }
            else {
                $state.Status.Text = ('No. {0} was not found.' -f $state.NumberPrefix)
            }
        })

        $grid.Add_CellClick({
            param($sender, $eventArgs)
            & $state.CopyHistoryRow $eventArgs.RowIndex
        })

        $grid.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.KeyCode -ne [System.Windows.Forms.Keys]::Enter -or $state.Grid.SelectedRows.Count -eq 0) {
                return
            }

            $eventArgs.SuppressKeyPress = $true
            & $state.CopyHistoryRow $state.Grid.SelectedRows[0].Index
        })

        $historyForm.Add_FormClosing({
            param($sender, $eventArgs)
            if ($eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
                $eventArgs.Cancel = $true
                $sender.Hide()
            }
        })

        $historyForm.Show()
        & $refreshHistoryGrid
        $grid.Focus()
    }

    $recordClipboard = {
        try {
            if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                $image = [System.Windows.Forms.Clipboard]::GetImage()
                try {
                    $fingerprint = Get-ClipboardImageFingerprint -Image $image
                    if ($fingerprint -cne $state.PreviousImageFingerprint) {
                        $source = Get-ClipboardSource
                        $wasRecorded = Add-ClipboardImageHistoryItem -Image $image -Path $HistoryPath -MaxHistory $MaxHistory -Source $source
                        $state.PreviousImageFingerprint = $fingerprint
                        if ($wasRecorded) { & $refreshHistoryGrid }
                    }
                }
                finally {
                    $image.Dispose()
                }
                return
            }

            $content = Get-Clipboard -Raw -ErrorAction Stop
            if ($content -is [string] -and $content -cne $state.PreviousContent) {
                $source = Get-ClipboardSource
                $wasRecorded = Add-ClipboardHistoryItem -Content $content -Path $HistoryPath -MaxHistory $MaxHistory -MaxContentLength $MaxContentLength -Source $source
                $state.PreviousContent = $content
                $state.PreviousImageFingerprint = $null
                if ($wasRecorded) {
                    & $refreshHistoryGrid
                }
            }
        }
        catch {
            Write-Warning "Could not read the clipboard. Retrying: $($_.Exception.Message)"
            Write-WatchLog -Level WARN -Message "Could not read the clipboard: $($_.Exception.Message)"
        }
    }

    & $recordClipboard

    if ($RunOnce) {
        return
    }

    Write-WatchLog -Message 'Initializing tray icon and history window.'
    $applicationContext = [System.Windows.Forms.ApplicationContext]::new()
    $timer = [System.Windows.Forms.Timer]::new()
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $openMenuItem = $menu.Items.Add('Open history')
    $exitMenuItem = $menu.Items.Add('Exit')
    $notifyIcon = [System.Windows.Forms.NotifyIcon]::new()
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    $notifyIcon.Text = 'Clipboard History'
    $notifyIcon.ContextMenuStrip = $menu

    $timer.Interval = $IntervalMilliseconds
    $timer.Add_Tick($recordClipboard)
    $openMenuItem.Add_Click($openHistory)
    $notifyIcon.Add_DoubleClick($openHistory)
    $exitMenuItem.Add_Click({ $applicationContext.ExitThread() })

    $timer.Start()
    $notifyIcon.Visible = $true
    & $openHistory
    Write-WatchLog -Message 'Entering the message loop.'
    [System.Windows.Forms.Application]::Run($applicationContext)
    Write-WatchLog -Message 'Message loop exited normally.'
}
catch {
    Write-WatchLog -Level ERROR -Message "Unhandled exception: $($_.Exception.GetType().FullName): $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    throw
}
finally {
    if ($null -ne $notifyIcon) {
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
    }
    if ($null -ne $menu) {
        $menu.Dispose()
    }
    if ($null -ne $timer) {
        $timer.Dispose()
    }
    if ($null -ne $applicationContext) {
        $applicationContext.Dispose()
    }
    Write-WatchLog -Message 'Shutting down clipboard-watch.ps1.'
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
}
