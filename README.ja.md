# CatchMeUp

> macOS ネイティブの個人タスクアシスタント。スクリーンショット・テキスト・ファイル・フォルダ・URL を放り込むと、アイテムとタスクに整理し、「どこまでやったか／次に何をするか」を覚えてくれます。

[简体中文](README.md) · [English](README.en.md) · [Español](README.es.md) · **日本語** · [한국어](README.ko.md)

CatchMeUp は**単一ファイルのネイティブ macOS アプリ**（SwiftUI + Swift 6）。Electron も Python も不要で、DeepSeek API の呼び出し以外はすべてローカルで動作します。

---

## 機能

### 統合キャプチャ（WeChat 風・操作は最小限）
- 1 つの入力欄で何でも：**テキスト / URL / ファイルパス / ファイルをドロップ / フォルダをドロップ / スクショ貼り付け（⌘V）/ 範囲選択** — 種類は自動判別。
- スマート振り分け：URL は本文取得、パスは読み込み、画像は OCR か視覚モデルへ。
- グローバルホットキー（既定 `⌘⇧M`・**変更可**）：どこからでも範囲選択 → アプリが前面に出て解析。

### AI 整理（DeepSeek）
- 複数の AI プロバイダーに対応：**DeepSeek（既定）**、OpenAI、OpenRouter、Moonshot、Ollama、任意の OpenAI 互換エンドポイント。既定モデルは `deepseek-flash`（画像対応）。
- タイトル・要約・タグ・カテゴリに加え、2 種類の構造化結果を生成：
  - **タスク**：明確な締切があるもの；
  - **引き継ぎ**：プロジェクト整理（目標 / 全体像 / 詳細な進捗 / 次の一手 / リスク）。
- スクショはまず視覚モデル、失敗時は内蔵の **Vision OCR**（中国語＋英語）にフォールバック。
- フォルダは「README（あれば）＋ ディレクトリツリー ＋ 各ファイルの一行説明」に要約。全文は流し込みません。

### タスク（日付でグループ・ワンクリック）
- 「タスク」ビューは **期限切れ / 今日 / 明日 / 今週 / 以降 / 日付なし / 完了** でグループ化。
- 一行入力＋Return で作成。丸をクリックで完了、日付をクリックで変更、点で優先度変更。
- 時刻にローカル通知（アプリを閉じていても通知）。毎日 / 毎週 / 毎月の繰り返し対応。
- 締切付きタスクを**システムのカレンダー**に書き込むことも可能。

### 引き継ぎ（継続トラッキング）
- 各引き継ぎアイテムに「差分更新」ボタン：元データを再読み込みし、前回の引き継ぎを渡して、有効な進捗を保ったまま差分だけ追加。
- セッションの開始 / 終了と、Markdown でコピーできる引き継ぎサマリの生成。

### その他
- メニューバー：クイックメモ、スクショ、クリップボード、直近のタスク。
- **トークン使用量**（設定 → DeepSeek）：呼び出し / 入力 / 出力 / 合計、モデル別。
- API キーはローカルファイルに保存（キーチェーン不使用）— **許可ダイアログなし**。
- 権限（通知 / カレンダー / 画面収録）は**設定でボタンを押したときだけ**要求。起動時は何も出ません。
- **対応言語：简体中文 / English / Español / 日本語 / 한국어**（設定 → 言語。システム準拠か個別選択）。

---

## 動作環境

- macOS 14.0 以上（Apple Silicon で確認済み）
- Xcode または Command Line Tools（Swift 6）
- [DeepSeek](https://platform.deepseek.com/) の API キー
- 任意：Apple Development 証明書（権限を再ビルド後も保持。下記参照）

---

## クイックスタート

```bash
bash scripts/build.sh      # ビルドして dist/CatchMeUp.app を生成
open "dist/CatchMeUp.app"
bash scripts/test.sh       # または swift test
```

初回：

1. **設定 → DeepSeek** で API キーを貼り付けて**保存**。
2. **設定 → 権限** で必要なものを許可（通知 / カレンダー / 画面収録）。
3. `⌘⇧M`（**設定 → 一般**で変更可）で範囲選択して自動解析。

---

## 使い方

| 場面 | 操作 |
| --- | --- |
| テキストを記録 | ワークスペースの欄に入力して Return |
| ページを保存 | URL を貼り付けて Return |
| プロジェクトフォルダ整理 | フォルダをドロップ（引き継ぎとして処理） |
| スクショ整理 | `⌘⇧M`、カメラボタン、または ⌘V で貼り付け |
| アイテムを見る | カードをクリック → 別ウィンドウ（移動・リサイズ可、「更新」あり） |
| タスク | タスクタブで一行入力。期限・優先度・完了を行内で操作 |
| 引き継ぎ | 引き継ぎタブで生成、またはカードで更新 |

---

## 構成

```text
catchmeup/
├── Package.swift                 # SwiftPM（macOS 14+、外部依存なし）
├── Sources/
│   ├── CatchMeUpCore/            # モデル・保存・AI・OCR・カレンダー・通知
│   │   └── L10n.swift            # ローカライズ（zh/en/es/ja/ko）
│   └── CatchMeUpApp/             # SwiftUI レイヤ
├── Tests/CatchMeUpCoreTests/
└── scripts/
```

---

## データとプライバシー

- データフォルダ：`~/Library/Application Support/CatchMeUp/`（`catchmeup.db`、`storage/`、`secrets.json`、`usage.json`）。
- API キーは `secrets.json`（0600）。環境変数 `DEEPSEEK_API_KEY` でも上書き可。
- DeepSeek は整理時のみ呼び出し。それ以外は端末内に留まります。

---

## 権限と署名

macOS は画面収録などの権限を**コード署名**で記憶します。**ad-hoc 署名**では指定要件がビルドごとに変わる `cdhash` になり、再ビルドのたびに新しいアプリ扱いで再要求されます。

`scripts/build.sh` は可能なら **Apple Development 証明書**で署名し、権限が持続します：

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" bash scripts/build.sh
```

個人情報を含まない**配布用ビルド**（GitHub Release など）：

```bash
bash scripts/package-release.sh   # → dist/CatchMeUp-<version>.zip（ad-hoc、メール/Team ID なし）
```

---

## FAQ

**Q: 画面収録の許可を何度も求められる。**
A: 証明書で再ビルド（上記）し、設定 → 権限で一度許可してください。

**Q: 権限なしでも使える？**
A: 使えます。通知・カレンダー・スクショだけが使えなくなります。

**Q: DeepSeek なしでも？**
A: 整理と引き継ぎは API 依存です。キーがなくても手動でタスク管理は可能です。

---

## ライセンス

[MIT](LICENSE)
