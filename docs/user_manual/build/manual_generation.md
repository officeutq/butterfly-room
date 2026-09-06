# 操作マニュアル DOCX 生成手順

このファイルは、`docs/user_manual/manual.md` から Google Docs（Google ドキュメント）へ取り込むための `docs/user_manual/build/manual.docx` を作成した手順を記録するものです。

> 2026-09-06時点では、店舗登録の初回店舗設定・公開フローを`manual.md`へ反映済みですが、新画面の再撮影前のため`manual.docx`は再生成していません。次回は新しい3画像を取得してからDOCXを再生成・検証します。

## 入力ファイル

- `docs/user_manual/manual.md`
  - 読者向けに統合した操作マニュアル本文です。
  - 画像は `images/...` の相対パスで参照します。

## 出力ファイル

- `docs/user_manual/build/manual.docx`
  - Google Docs（Google ドキュメント）への取り込み対象ファイルです。
- `docs/user_manual/build/manual.docx.check.md`
  - DOCX（Word 文書）生成後の検証結果です。

## 今回の生成方針

今回の環境では Pandoc（文書変換ツール）と LibreOffice / soffice（オフィス文書変換ツール）が見つからなかったため、Codex の bundled Python（同梱 Python 実行環境）と `python-docx`（Word 文書生成ライブラリ）で DOCX を生成しました。

`manual.docx` は次の方針で作成しています。

- `manual.md` の見出し、箇条書き、番号付きリスト、注意書き、TODO を反映する。
- `manual.md` で参照している画像を DOCX 内の `word/media/` に埋め込む。
- Google Docs（Google ドキュメント）へ取り込んだときに過度な装飾が残りにくいよう、フォントと見出し装飾は控えめにする。
- 読者向け文書に撮影用アカウント、固定パスワード、Playwright（ブラウザ自動操作）実行コマンド、ローカル撮影用 Rails task（Rails タスク）を含めない。

## Google Docs 向け後処理

生成後に Google Docs（Google ドキュメント）取り込み時のタイトル罫線崩れを避けるため、`google_docs_title_sanitize.py` を実行しました。

```powershell
$py = "<bundled-python>\python.exe"
$sanitizer = "<documents-skill>\scripts\google_docs_title_sanitize.py"
& $py $sanitizer docs/user_manual/build/manual.raw.docx --out docs/user_manual/build/manual.docx
& $py $sanitizer docs/user_manual/build/manual.docx --check
```

## Google Docs への取り込み手順

1. Google Drive（Google ドライブ）を開きます。
2. `docs/user_manual/build/manual.docx` をアップロードします。
3. アップロードした DOCX（Word 文書）を右クリックし、Google Docs（Google ドキュメント）で開きます。
4. 画像、見出し、箇条書き、TODO 表記が崩れていないか確認します。
5. Google Docs 側で編集する場合も、Git 管理上の原本は `docs/user_manual/manual.md` として扱います。
6. Google Docs 側で本文を変更した場合は、必要に応じて `docs/user_manual/manual.md` に反映します。

## 再生成時の注意

- `manual.md` では画像パスを `images/...` の相対パスにしてください。
- `manual.md` にはローカル撮影用の内部情報を入れないでください。
- Pandoc（文書変換ツール）を使う再生成手順は、この環境では未確認です。
- 再現性を高める場合は、次回以降に DOCX 生成用 script（スクリプト）をリポジトリ内へ追加するか検討してください。
