$modulePath = Join-Path $PSScriptRoot '..\ClipboardHistory.psm1'
Import-Module $modulePath -Force

Describe 'ClipboardHistory' {
    BeforeEach {
        $script:historyPath = Join-Path $TestDrive 'history.json'
    }

    It 'creates history and stores a full text value' {
        Add-ClipboardHistoryItem -Content "line one`nline two" -Path $historyPath | Should -BeTrue
        $items = @(Get-ClipboardHistory -Path $historyPath)
        $items.Count | Should -Be 1
        $items[0].content | Should -Be "line one`nline two"
        $items[0].useCount | Should -Be 1
    }

    It 'deduplicates content and increments its use count' {
        Add-ClipboardHistoryItem -Content 'git status' -Path $historyPath | Out-Null
        Add-ClipboardHistoryItem -Content 'git status' -Path $historyPath | Out-Null
        $items = @(Get-ClipboardHistory -Path $historyPath)
        $items.Count | Should -Be 1
        $items[0].useCount | Should -Be 2
    }

    It 'keeps only the requested number of most recently used items' {
        Add-ClipboardHistoryItem -Content 'first' -Path $historyPath -MaxHistory 2 | Out-Null
        Start-Sleep -Milliseconds 5
        Add-ClipboardHistoryItem -Content 'second' -Path $historyPath -MaxHistory 2 | Out-Null
        Start-Sleep -Milliseconds 5
        Add-ClipboardHistoryItem -Content 'third' -Path $historyPath -MaxHistory 2 | Out-Null
        (@(Get-ClipboardHistory -Path $historyPath)).content | Should -Be @('third', 'second')
    }

    It 'rejects whitespace-only and oversized content' {
        Add-ClipboardHistoryItem -Content '   ' -Path $historyPath | Should -BeFalse
        Add-ClipboardHistoryItem -Content '12345' -Path $historyPath -MaxContentLength 4 | Should -BeFalse
        Test-Path -LiteralPath $historyPath | Should -BeTrue
    }

    It 'backs up malformed JSON and returns an empty history' {
        Set-Content -LiteralPath $historyPath -Value '{not json' -NoNewline
        @(Get-ClipboardHistory -Path $historyPath).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $TestDrive -Filter 'history.json.corrupt-*').Count | Should -Be 1
    }

    It 'creates a one-line preview without altering stored data' {
        Get-ClipboardHistoryPreview -Content "SELECT`nFROM users" -Length 100 | Should -Be 'SELECT FROM users'
    }
}
