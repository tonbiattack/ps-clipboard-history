[CmdletBinding()]
param(
    [string] $HistoryPath,
    [ValidateRange(50, 60000)][int] $IntervalMilliseconds = 500,
    [ValidateRange(1, 2147483647)][int] $MaxHistory = 50,
    [ValidateRange(1, 2147483647)][int] $MaxContentLength = 10000,
    [switch] $RunOnce,
    [string] $MutexName = 'Local\PsClipboardHistoryWatch',
    [switch] $DisableHotkey
)

Import-Module (Join-Path $PSScriptRoot 'ClipboardHistory.psm1') -Force

$mutex = [System.Threading.Mutex]::new($false, $MutexName)
if (-not $mutex.WaitOne(0, $false)) {
    Write-Host 'clipboard-watch.ps1 is already running.'
    exit 1
}

try {
    $state = [pscustomobject]@{
        PreviousContent = $null
        IsRefreshing    = $false
        HistoryForm     = $null
        Grid            = $null
        Status          = $null
    }

    $refreshHistoryGrid = {
        if ($null -eq $state.Grid -or $state.HistoryForm.IsDisposed) {
            return
        }

        $selectedContent = $null
        if ($state.Grid.SelectedRows.Count -gt 0) {
            $selectedContent = [string]$state.Grid.SelectedRows[0].Tag
        }

        $state.IsRefreshing = $true
        try {
            $state.Grid.Rows.Clear()
            $items = @(Get-ClipboardHistory -Path $HistoryPath)
            $selectedRow = $null
            foreach ($item in $items) {
                $rowIndex = $state.Grid.Rows.Add(
                    ([datetime]$item.lastUsedAt).ToString('yyyy/MM/dd HH:mm:ss'),
                    (Get-ClipboardHistoryPreview -Content ([string]$item.content))
                )
                $row = $state.Grid.Rows[$rowIndex]
                $row.Tag = [string]$item.content
                if ($row.Tag -ceq $selectedContent) {
                    $selectedRow = $row
                }
            }

            if ($null -ne $selectedRow) {
                $selectedRow.Selected = $true
            }
        }
        finally {
            $state.IsRefreshing = $false
        }
    }

    $openHistory = {
        if ($null -ne $state.HistoryForm -and -not $state.HistoryForm.IsDisposed) {
            $state.HistoryForm.Show()
            $state.HistoryForm.Activate()
            return
        }

        $historyForm = [System.Windows.Forms.Form]::new()
        $historyForm.Text = 'Clipboard history'
        $historyForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $historyForm.Size = [System.Drawing.Size]::new(980, 560)
        $historyForm.MinimumSize = [System.Drawing.Size]::new(640, 360)

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

        [void]$grid.Columns.Add('LastUsed', 'Last used')
        [void]$grid.Columns.Add('Preview', 'Preview')
        $grid.Columns['LastUsed'].Width = 150
        $grid.Columns['Preview'].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill

        $status = [System.Windows.Forms.Label]::new()
        $status.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $status.Height = 28
        $status.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 0)
        $status.Text = 'New copies appear automatically. Select a row to copy it.'

        $historyForm.Controls.Add($grid)
        $historyForm.Controls.Add($status)
        $state.HistoryForm = $historyForm
        $state.Grid = $grid
        $state.Status = $status

        $grid.Add_CellClick({
            param($sender, $eventArgs)
            if ($state.IsRefreshing -or $eventArgs.RowIndex -lt 0) {
                return
            }

            $content = [string]$state.Grid.Rows[$eventArgs.RowIndex].Tag
            if ([string]::IsNullOrWhiteSpace($content)) {
                return
            }

            Set-Clipboard -Value $content
            Use-ClipboardHistoryItem -Content $content -Path $HistoryPath -MaxHistory $MaxHistory | Out-Null
            $state.PreviousContent = $content
            $state.Status.Text = 'Copied to clipboard. Arrow keys only change selection.'
            & $refreshHistoryGrid
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
    }

    $recordClipboard = {
        try {
            $content = Get-Clipboard -Raw -ErrorAction Stop
            if ($content -is [string] -and $content -cne $state.PreviousContent) {
                $wasRecorded = Add-ClipboardHistoryItem -Content $content -Path $HistoryPath -MaxHistory $MaxHistory -MaxContentLength $MaxContentLength
                $state.PreviousContent = $content
                if ($wasRecorded) {
                    & $refreshHistoryGrid
                }
            }
        }
        catch {
            Write-Warning "Could not read the clipboard. Retrying: $($_.Exception.Message)"
        }
    }

    & $recordClipboard

    if ($RunOnce) {
        return
    }

    if ($DisableHotkey) {
        while ($true) {
            Start-Sleep -Milliseconds $IntervalMilliseconds
            & $recordClipboard
        }
    }

    if (-not ('ClipboardHistoryHotkeyForm' -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class ClipboardHistoryHotkeyForm : Form
{
    private const int WM_HOTKEY = 0x0312;
    private const int HotkeyId = 0x4348;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint VirtualKeyV = 0x56;

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event EventHandler HotkeyPressed;
    public bool IsHotkeyRegistered { get; private set; }

    public ClipboardHistoryHotkeyForm()
    {
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Location = new Point(-2000, -2000);
        Size = new Size(1, 1);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        IsHotkeyRegistered = RegisterHotKey(Handle, HotkeyId, ModControl | ModAlt, VirtualKeyV);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HotkeyId && HotkeyPressed != null)
        {
            HotkeyPressed(this, EventArgs.Empty);
        }
        base.WndProc(ref m);
    }

    protected override void Dispose(bool disposing)
    {
        if (IsHandleCreated && IsHotkeyRegistered)
        {
            UnregisterHotKey(Handle, HotkeyId);
            IsHotkeyRegistered = false;
        }
        base.Dispose(disposing);
    }
}
'@
    }

    $form = [ClipboardHistoryHotkeyForm]::new()
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
    $form.Add_HotkeyPressed($openHistory)
    $openMenuItem.Add_Click($openHistory)
    $notifyIcon.Add_DoubleClick($openHistory)
    $exitMenuItem.Add_Click({ $form.Close() })

    $timer.Start()
    $notifyIcon.Visible = $true
    & $openHistory
    [System.Windows.Forms.Application]::Run($form)
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
    if ($null -ne $form) {
        $form.Dispose()
    }
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
}
