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
    $previousContent = $null

    $recordClipboard = {
        try {
            $content = Get-Clipboard -Raw -ErrorAction Stop
            if ($content -is [string] -and $content -cne $previousContent) {
                Add-ClipboardHistoryItem -Content $content -Path $HistoryPath -MaxHistory $MaxHistory -MaxContentLength $MaxContentLength | Out-Null
                $previousContent = $content
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
    $timer.Interval = $IntervalMilliseconds
    $timer.Add_Tick($recordClipboard)
    $form.Add_HotkeyPressed({
        Show-ClipboardHistoryPicker -Path $HistoryPath -MaxHistory $MaxHistory | Out-Null
    })

    $timer.Start()
    [System.Windows.Forms.Application]::Run($form)
}
finally {
    if ($null -ne $timer) {
        $timer.Dispose()
    }
    if ($null -ne $form) {
        $form.Dispose()
    }
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
}
