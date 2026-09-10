Describe 'install-shortcut.ps1' {
    BeforeEach {
        $script:installScript = Join-Path $PSScriptRoot '..\install-shortcut.ps1'
        $script:shortcutDirectory = Join-Path $TestDrive 'shortcuts'
        $script:watcherShortcutDirectory = Join-Path $TestDrive 'startup'
    }

    It 'creates a desktop-style shortcut for the selector with Ctrl+Alt+V' {
        & $installScript -ShortcutDirectory $shortcutDirectory -WatcherShortcutDirectory $watcherShortcutDirectory

        $shortcutPath = Join-Path $shortcutDirectory 'Clipboard History.lnk'
        Test-Path -LiteralPath $shortcutPath | Should -BeTrue

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.Arguments | Should -Match 'clipboard-select\.ps1'
        $shortcut.Arguments | Should -Match '-NoProfile'
        $shortcut.Arguments | Should -Match '-ExecutionPolicy Bypass'
        $shortcut.Arguments | Should -Match '-WindowStyle Hidden'
        $shortcut.Hotkey | Should -Match '^(Alt\+Ctrl|Ctrl\+Alt)\+V$'

        $watcherShortcutPath = Join-Path $watcherShortcutDirectory 'Clipboard History Watcher.lnk'
        Test-Path -LiteralPath $watcherShortcutPath | Should -BeTrue
        $watcherShortcut = $shell.CreateShortcut($watcherShortcutPath)
        $watcherShortcut.TargetPath | Should -Match 'wscript\.exe$'
        $watcherShortcut.Arguments | Should -Match 'clipboard-watch\.vbs'
    }

    It 'does not overwrite an existing shortcut without Force' {
        New-Item -ItemType Directory -Path $shortcutDirectory | Out-Null
        New-Item -ItemType File -Path (Join-Path $shortcutDirectory 'Clipboard History.lnk') | Out-Null

        { & $installScript -ShortcutDirectory $shortcutDirectory -WatcherShortcutDirectory $watcherShortcutDirectory } | Should -Throw '*already exists*'
    }
}
