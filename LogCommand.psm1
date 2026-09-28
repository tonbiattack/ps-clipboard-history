Set-StrictMode -Version Latest

function Assert-SingleLineLogValue {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name must not be empty."
    }
    if ($Value -match "[\r\n]") {
        throw "$Name must be a single line."
    }
}

function ConvertTo-PosixShellLiteral {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Value)

    # シングルクォートで囲み、パスや検索語をシェルのオプション・展開として解釈させません。
    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $escapedSingleQuote = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
    return $singleQuote + $Value.Replace($singleQuote, $escapedSingleQuote) + $singleQuote
}

function New-LinuxLogCommand {
    param(
        [Parameter(Mandatory = $true)][string] $LogFile,
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
        [ValidateRange(1, 2147483647)][int] $Width = 2000
    )

    Assert-SingleLineLogValue -Name 'LogFile' -Value $LogFile
    $logFileLiteral = ConvertTo-PosixShellLiteral -Value $LogFile

    switch ($Preset) {
        'Open' {
            return "less -N -S -- $logFileLiteral"
        }
        'Tail' {
            return "tail -n $TailLines -- $logFileLiteral | less -S"
        }
        'Follow' {
            return "tail -n $TailLines -F -- $logFileLiteral"
        }
        'Search' {
            Assert-SingleLineLogValue -Name 'Needle' -Value $Needle
            $needleLiteral = ConvertTo-PosixShellLiteral -Value $Needle
            return "grep -F -n -m $MaxMatches -C $ContextLines -- $needleLiteral $logFileLiteral | less -S"
        }
        'RecentSearch' {
            Assert-SingleLineLogValue -Name 'Needle' -Value $Needle
            $needleLiteral = ConvertTo-PosixShellLiteral -Value $Needle
            return "tail -n $RecentLines -- $logFileLiteral | grep -F -n -m $MaxMatches -C $ContextLines -- $needleLiteral | less -S"
        }
        'Exception' {
            $effectiveNeedle = if ([string]::IsNullOrWhiteSpace($Needle)) { 'Exception' } else { $Needle }
            Assert-SingleLineLogValue -Name 'Needle' -Value $effectiveNeedle
            $needleLiteral = ConvertTo-PosixShellLiteral -Value $effectiveNeedle
            return "grep -F -n -m $MaxMatches -B $ExceptionBeforeLines -A $ExceptionAfterLines -- $needleLiteral $logFileLiteral | less -S"
        }
        'Line' {
            if ($Line -lt 1) {
                throw 'Line must be greater than or equal to 1 when Preset is Line.'
            }
            return ("sed -n '{0}p' -- {1} | less -S" -f $Line, $logFileLiteral)
        }
        'Slice' {
            if ($Line -lt 1) {
                throw 'Line must be greater than or equal to 1 when Preset is Slice.'
            }
            $awkProgram = '{ print substr($0, start, width) }'
            return ("sed -n '{0}p' -- {1} | awk -v start={2} -v width={3} '{4}'" -f $Line, $logFileLiteral, $Start, $Width, $awkProgram)
        }
    }
}

Export-ModuleMember -Function ConvertTo-PosixShellLiteral, New-LinuxLogCommand
