$modulePath = Join-Path $PSScriptRoot '..\LogCommand.psm1'
Import-Module $modulePath -Force

Describe 'Linux log command generator' {
    It 'creates a less command from only a log file path' {
        New-LinuxLogCommand -LogFile '/var/log/my-app/application.log' |
            Should -Be "less -N -S -- '/var/log/my-app/application.log'"
    }

    It 'quotes a single quote in the log file path safely for a POSIX shell' {
        $singleQuote = [string][char]39
        $doubleQuote = [string][char]34
        $escapedQuote = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
        $expectedPath = $singleQuote + '/var/log/O' + $escapedQuote + 'Reilly/app.log' + $singleQuote

        New-LinuxLogCommand -LogFile "/var/log/O'Reilly/app.log" |
            Should -Be ('less -N -S -- ' + $expectedPath)
    }

    It 'creates a fixed-string search with surrounding context' {
        New-LinuxLogCommand -LogFile '/var/log/app.log' -Preset Search -Needle 'upstream timeout' |
            Should -Be "grep -F -n -m 20 -C 3 -- 'upstream timeout' '/var/log/app.log' | less -S"
    }

    It 'requires a search string for the search presets' {
        { New-LinuxLogCommand -LogFile '/var/log/app.log' -Preset Search } |
            Should -Throw '*Needle must not be empty*'
    }

    It 'creates a bounded slice of one log line for sharing' {
        New-LinuxLogCommand -LogFile '/var/log/app.log' -Preset Slice -Line 418 -Start 2001 -Width 2000 |
            Should -Be "sed -n '418p' -- '/var/log/app.log' | awk -v start=2001 -v width=2000 '{ print substr(`$0, start, width) }'"
    }
}
