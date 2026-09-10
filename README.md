# ps-clipboard-history

Windows のテキストクリップボードをローカル JSON に保存し、あとから選び直せる PowerShell 専用ツールです。外部通信や管理者権限は必要ありません。

## 要件

- Windows PowerShell 5.1 以降（PowerShell 7 でも動作）
- `Get-Clipboard` / `Set-Clipboard` が利用可能な Windows

## 使い方

監視を開始します。既定では 500ms ごとに確認し、`%LOCALAPPDATA%\clipboard-history\history.json` に最大 50 件を保存します。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\clipboard-watch.ps1
```

初回だけ、履歴画面を起動するデスクトップショートカットを作成します。

```powershell
.\install-shortcut.ps1
```

作成される **Clipboard History** ショートカットは `clipboard-select.ps1` を `-NoProfile` とプロセス限定の `-ExecutionPolicy Bypass` で起動します。システム全体の実行ポリシーは変更しません。既存の同名ショートカットを置き換える場合は `-Force` を付けてください。

既定のショートカットキーは `Ctrl + Alt + V` です。ショートカットのプロパティから変更できます。`Win + V` は変更せず、Windows 標準のクリップボード履歴として併用します。

`Out-GridView` が使える環境では一覧ウィンドウを開きます。使えない環境では番号入力に切り替わります。必要であれば直接起動もできます。

```powershell
.\clipboard-select.ps1
```

スタートメニューの「プログラム」フォルダに作成する場合は、次のように実行します。

```powershell
.\install-shortcut.ps1 -Destination StartMenu
```

## オプション

両方のスクリプトは `-HistoryPath` と `-MaxHistory` を受け取ります。監視スクリプトには `-IntervalMilliseconds`（既定 500）、`-MaxContentLength`（既定 10000）、テスト向けの `-RunOnce` もあります。

```powershell
.\clipboard-watch.ps1 -HistoryPath "$env:TEMP\history.json" -MaxHistory 100
```

空白のみ・10,000 文字超の内容は保存せず、重複するテキストは新規登録せずに使用回数と最終利用時刻だけを更新します。JSON が壊れている場合は同じフォルダに `.corrupt-日時` 付きで退避してから、新しい履歴を作ります。

履歴には機微情報をコピーしないでください。保存内容は暗号化されません。
