# Frontend Architecture（フロントエンド設計）

## 1. 概要

本アプリのフロントエンドは Rails Views + Hotwire（Turbo / Stimulus）を中心に構成される。
SPAではなく、サーバーサイドレンダリングされたHTMLを基本とし、必要な操作だけStimulusで補助する。

---

## 2. 基本方針

- Rails Viewを画面の正本とする
- Turbo Frame / Turbo Stream で部分更新する
- Stimulus Controller はUI状態・ブラウザAPI・外部SDK連携を担当する
- フロントエンド側に業務ロジックを持ちすぎない
- Rails UJS は使用しない
- Importmap 構成を前提とする

---

## 3. Stimulus Controller の役割分類

### 3.1 配信系

```text
ivs_publisher_controller
ivs_viewer_controller
live_stage_controller
stream_debug_controller
```

役割:

- IVS Stage 参加
- 映像/音声トラック管理
- 配信開始/終了API連携
- 視聴者側の受信制御
- ライブ画面の高さ・キーボード対応

---

### 3.2 視聴体験系

```text
viewer_page_controller
viewer_drink_panel_controller
comment_panel_controller
presence_poll_controller
```

役割:

- live / waiting 表示切替
- ドリンクパネル開閉
- コメント欄自動スクロール
- 視聴者数更新

---

### 3.3 UI補助系

```text
modal_controller
clipboard_controller
share_controller
favorite_sync_controller
auto_redirect_controller
install_prompt_controller
onboarding_controller
```

役割:

- Bootstrapモーダル制御
- クリップボードコピー
- Web Share API連携
- お気に入り状態同期
- 自動リダイレクト
- PWAインストール導線
- 店舗向けオンボーディング

---

### 3.4 画像アップロード系

```text
image_upload_controller
filepond_verification_controller
```

役割:

- FilePond 初期化
- クライアントサイドリサイズ
- JPEG変換
- 既存画像削除フラグ制御

---

### 3.5 美顔・エフェクト検証系

```text
banuba_verification_controller
deepar_verification_controller
```

役割:

- Banuba / DeepAR の単体検証
- SDKロード確認
- エフェクト動作確認

---

## 4. View構成

主なViewグループ:

```text
views/home
views/booths
views/cast/booths
views/cast/stream_sessions
views/stream_sessions
views/admin
views/system_admin
views/favorites
views/wallet
views/legal
views/layouts
```

### 4.1 layout

```text
application.html.erb
_default_main.html.erb
_fixed_subnav_main.html.erb
_viewer_main.html.erb
_cast_live_main.html.erb
_header.html.erb
_footer.html.erb
```

役割:

- 通常画面
- 固定サブナビ付き画面
- 視聴ページ
- キャスト配信ページ
- ヘッダー/フッター

---

## 5. ライブ画面レイアウト

live_stage_controller が以下を担当する。

- `--live-stage-h`
- `--viewer-stage-h`
- `--app-header-h`
- `--app-footer-h`

モバイルではキーボード表示時に body class を切り替える。

```text
keyboard-open
cast-live-keyboard-open
viewer-keyboard-open
```

これにより、コメント入力時やタイトル入力時に映像・フォームが崩れにくい構成になっている。

---

## 6. お気に入り同期

favorite_sync_controller は同一キーを持つ複数のお気に入りボタンを同期する。

```text
data-favorite-sync-key-value
```

同じ対象が複数画面部品に表示されても、1つの操作で全ボタンの見た目を揃える。

---

## 7. 共有機能

share_controller は Web Share API を使う。

- Web Share API が利用可能な場合はOS共有を起動
- 利用不可の場合は警告フラッシュを表示
- 店舗向けオンボーディング中は共有完了後にstep更新を通知する

---

## 8. 画像アップロード

image_upload_controller は FilePond を利用する。

仕様:

- 単一ファイル
- プレビューあり
- クライアントサイドリサイズ
- 1024x1024 を基本
- アップスケールなし
- JPEG変換
- 品質94
- 背景白
- HEIC / HEIF / WebP / PNG / JPEG を受け付ける

---

## 9. 設計上の注意点

- Stimulus Controller が増えているため、責務ごとの整理が重要
- IVS publisher は大きくなりやすいため、既に分割されている submodule を維持する
- UI状態はDOMを正本にしすぎず、必要最小限にする
- Turbo before-cache 時のcleanupを忘れない
