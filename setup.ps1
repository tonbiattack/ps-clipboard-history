[CmdletBinding()]
param()

Set-StrictMode -Version Latest

# 既存プロセスを止めてからショートカットを更新し、二重起動を避けて再起動します。
$installerPath = Join-Path $PSScriptRoot 'install-shortcut.ps1'
$watcherLauncherPath = Join-Path $PSScriptRoot 'clipboard-watch.vbs'

Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessId -ne $PID -and
        -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
        $_.CommandLine.IndexOf($PSScriptRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $_.CommandLine -match 'clipboard-(watch|select)\.(ps1|vbs)'
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
    }

# デスクトップとスタートアップのショートカットを現在の配置先で作り直します。
& $installerPath -Force

$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
if (-not (Test-Path -LiteralPath $wscript -PathType Leaf)) {
    $wscript = (Get-Command wscript.exe -ErrorAction Stop).Source
}

# wscript.exe 経由にすることで、通常起動時にコンソールを表示しません。
Start-Process -FilePath $wscript -ArgumentList ('"{0}"' -f $watcherLauncherPath)
Write-Host 'Setup complete. Clipboard History has been restarted in the notification area.'
