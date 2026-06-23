# manual.docx 検証結果

検証日時: 2026-06-23 12:28:03 +09:00

## 対象

- Markdown（統合マニュアル原本）: `docs/user_manual/manual.md`
- DOCX（Word 文書）: `docs/user_manual/build/manual.docx`

## 構造確認

- `manual.md` 行数: 861
- `manual.md` サイズ: 42,522 bytes
- `manual.md` の画像参照数: 108
- `manual.md` の画像参照はすべて `images/...` の相対パス
- `manual.docx` サイズ: 12,066,552 bytes
- `manual.docx` の `word/media/` 画像数: 108
- `manual.docx` の本文段落数: 582
- `manual.docx` の画像描画要素数: 108

## 内部情報の混入確認

`docs/user_manual/manual.md` で次の内部向け文字列が検出されないことを確認しました。

- `manual+`
- `ManualCapture123`
- `manual_capture`
- `npm run`
- `docker compose`
- `Playwright`
- `example.test`
- `C:/`
- `C:\`

## Google Docs 向け後処理

`google_docs_title_sanitize.py` による確認結果:

```text
[OK] no Google Docs title border/rule residue detected
```

## レンダリング確認

`render_docx.py` による DOCX（Word 文書）のページ画像レンダリングを試しましたが、現在の環境では LibreOffice / soffice（オフィス文書変換ツール）が見つからず、ページ画像化は未実施です。

```text
FileNotFoundError: [WinError 2] 指定されたファイルが見つかりません。
```

代替確認として、DOCX 内部の `word/document.xml` と `word/media/` を直接確認し、本文と画像が含まれていることを確認しました。

## 未確認点

- Google Docs（Google ドキュメント）へ実際にアップロードした後の表示崩れ。
- Pandoc（文書変換ツール）を利用した再生成手順。
- LibreOffice / soffice（オフィス文書変換ツール）がある環境でのページ画像レンダリング確認。
