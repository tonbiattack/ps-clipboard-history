[CmdletBinding()]
param(
    [string] $HistoryPath,
    [ValidateRange(50, 60000)][int] $IntervalMilliseconds = 500,
    [ValidateRange(1, 2147483647)][int] $MaxHistory = 50,
    [ValidateRange(1, 2147483647)][int] $MaxContentLength = 10000,
    [switch] $RunOnce,
    [string] $MutexName = 'Local\PsClipboardHistoryWatch'
)

Import-Module (Join-Path $PSScriptRoot 'ClipboardHistory.psm1') -Force

$mutex = [System.Threading.Mutex]::new($false, $MutexName)
if (-not $mutex.WaitOne(0, $false)) {
    Write-Host 'clipboard-watch.ps1 is already running.'
    exit 1
}

try {
    $previousContent = $null
    do {
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

        if (-not $RunOnce) {
            Start-Sleep -Milliseconds $IntervalMilliseconds
        }
    } while (-not $RunOnce)
}
finally {
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
}
