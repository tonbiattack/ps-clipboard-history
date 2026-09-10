# ps-clipboard-history

Windows のテキストクリップボードをローカル JSON に保存し、あとから選び直せる PowerShell 専用ツールです。外部通信、管理者権限、インストールは必要ありません。

## 要件

- Windows PowerShell 5.1 以降（PowerShell 7 でも動作）
- `Get-Clipboard` / `Set-Clipboard` が利用可能な Windows

## 使い方

監視を開始します。既定では 500ms ごとに確認し、`%LOCALAPPDATA%\clipboard-history\history.json` に最大 50 件を保存します。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\clipboard-watch.ps1
```

履歴を選択してクリップボードへ戻します。

```powershell
.\clipboard-select.ps1
```

`Out-GridView` が使える環境では一覧ウィンドウを開きます。使えない環境では番号入力に切り替わります。

## オプション

両方のスクリプトは `-HistoryPath` と `-MaxHistory` を受け取ります。監視スクリプトには `-IntervalMilliseconds`（既定 500）、`-MaxContentLength`（既定 10000）、テスト向けの `-RunOnce` もあります。

```powershell
.\clipboard-watch.ps1 -HistoryPath "$env:TEMP\history.json" -MaxHistory 100
```

空白のみ・10,000 文字超の内容は保存せず、重複するテキストは新規登録せずに使用回数と最終利用時刻だけを更新します。JSON が壊れている場合は同じフォルダに `.corrupt-日時` 付きで退避してから、新しい履歴を作ります。

履歴には機微情報をコピーしないでください。保存内容は暗号化されません。
