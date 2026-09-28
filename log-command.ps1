[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)][ValidateNotNullOrEmpty()][string] $LogFile,
    [ValidateSet('Open', 'Tail', 'Search', 'RecentSearch', 'Exception', 'Follow', 'Line', 'Slice')]
    [string] $Preset = 'Open',
    [string] $Needle,
    [ValidateRange(1, 2147483647)][int] $TailLines = 300,
    [ValidateRange(1, 2147483647)][int] $RecentLines = 20000,
    [ValidateRange(1, 2147483647)][int] $MaxMatches = 20,
    [ValidateRange(0, 2147483647)][int] $ContextLines = 3,
    [ValidateRange(0, 2147483647)][int] $ExceptionBeforeLines = 3,
    [ValidateRange(0, 2147483647)][int] $ExceptionAfterLines = 50,
    [int] $Line,
    [ValidateRange(1, 2147483647)][int] $Start = 1,
    [ValidateRange(1, 2147483647)][int] $Width = 2000,
    [switch] $NoCopy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LogCommand.psm1') -Force

# 定型コマンドだけを生成し、OpenShiftやSSHへ接続・実行はしません。
# 出力を許可済みのLinuxターミナルへ貼り付ける利用を想定しています。
$commandParameters = @{
    LogFile               = $LogFile
    Preset                = $Preset
    Needle                = $Needle
    TailLines             = $TailLines
    RecentLines           = $RecentLines
    MaxMatches            = $MaxMatches
    ContextLines          = $ContextLines
    ExceptionBeforeLines  = $ExceptionBeforeLines
    ExceptionAfterLines   = $ExceptionAfterLines
    Line                  = $Line
    Start                 = $Start
    Width                 = $Width
}

$command = New-LinuxLogCommand @commandParameters
Write-Output $command

if (-not $NoCopy) {
    Set-Clipboard -Value $command
    Write-Host 'Copied the Linux log command to the clipboard.'
}
