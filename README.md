# ps-clipboard-history

Windows のテキストクリップボードをローカル JSON に保存し、あとから選び直せる PowerShell 専用ツールです。外部通信や管理者権限は必要ありません。

## 要件

- Windows PowerShell 5.1 以降（PowerShell 7 でも動作）
- `Get-Clipboard` / `Set-Clipboard` が利用可能な Windows

## 使い方

監視は通知領域（タスクバー右端）にアイコンを置く常駐アプリとして動作します。コンソールを表示せず、既定では 500ms ごとに確認し、`%LOCALAPPDATA%\clipboard-history\history.json` に最大 50 件を保存します。

初回・更新時ともに、リポジトリのフォルダで次の1コマンドだけ実行してください。

```powershell
.\setup.ps1
```

このコマンドは、古い本ツールのプロセスを終了してから、デスクトップの履歴ショートカット作成、ログイン時の自動起動設定、常駐アプリの起動をまとめて行います。デスクトップの **Clipboard History** も常駐アプリを開くため、旧方式の一覧画面は開きません。スタートメニューには項目を作成しません。

作成される **Clipboard History** ショートカットは履歴一覧を開きます。同時に、ログイン時に常駐アプリを起動する **Clipboard History Watcher** ショートカットを現在ユーザーのスタートアップフォルダへ作成します。どちらも `-NoProfile` とプロセス限定の `-ExecutionPolicy Bypass` を使用し、システム全体の実行ポリシーは変更しません。既存の本ツールのショートカットは更新します。

常駐アプリを起動すると、履歴ウィンドウは開いたままになります。`Ctrl + C` すると新しいコピー内容が自動で先頭に追加されます。マウスで行をクリック、または上下矢印キーで行を選んで `Enter` を押すと、その内容をクリップボードへ戻します。上下矢印キーだけではコピーしません。カウント列は表示しません。閉じるボタンはウィンドウを隠すだけで監視を続けます。通知領域の **Clipboard History** アイコンをダブルクリックまたは右クリック→「Open history」で再表示できます。右クリック→「Exit」で常駐を終了できます。`Ctrl + Alt + V` も補助として使えます。`Win + V` は変更せず、Windows 標準のクリップボード履歴として併用します。

## オプション

両方のスクリプトは `-HistoryPath` と `-MaxHistory` を受け取ります。監視スクリプトには `-IntervalMilliseconds`（既定 500）、`-MaxContentLength`（既定 10000）、テスト向けの `-RunOnce` と `-MutexName` もあります。

```powershell
.\clipboard-watch.ps1 -HistoryPath "$env:TEMP\history.json" -MaxHistory 100
```

空白のみ・10,000 文字超の内容は保存せず、重複するテキストは新規登録せずに使用回数と最終利用時刻だけを更新します。JSON が壊れている場合は同じフォルダに `.corrupt-日時` 付きで退避してから、新しい履歴を作ります。

履歴には機微情報をコピーしないでください。保存内容は暗号化されません。
