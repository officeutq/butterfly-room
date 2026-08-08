# Uploads / Assets 設計

## 1. 概要

本アプリでは、プロフィール画像・ブース画像・店舗画像などの画像アップロードに FilePond を利用する。
アップロード前にクライアントサイドでリサイズ・JPEG変換を行う。ただし、HEIC/HEIF はブラウザによって変換できないため、クライアント側の変換結果だけを保存可否の根拠にしない。

---

## 2. 対象Controller

```text
image_upload_controller
filepond_verification_controller
```

---

## 3. image_upload_controller 仕様

### 3.1 入力

targets:

```text
input
removeFlag
```

values:

```text
initialUrl
width
height
```

### 3.2 FilePond設定

```text
allowMultiple: false
allowImagePreview: true
allowImageResize: true
allowImageTransform: true
allowProcess: false
storeAsFile: true
```

### 3.3 リサイズ

```text
target width: value または 1024
target height: value または 1024
mode: contain
upscale: false
```

### 3.4 変換

```text
mime type: image/jpeg
quality: 94
background: #ffffff
```

### 3.5 対応形式

```text
image/jpeg
image/png
image/webp
image/heic
image/heif
```

---

## 4. サーバー側の画像正規化

### 4.1 画像変換

`ImageAttachments::NormalizeService` は、アップロードされた画像を Active Storage へ保存する前に JPEG へ正規化するための共通 Service（業務処理を集約するクラス）である。

- 拡張子とリクエストの `content_type` は信用せず、ImageMagick が読み取った実体形式で判定する
- 入力形式は JPEG / PNG / WebP / HEIC / HEIF とする
- 複数画像を含むファイルは先頭画像のみを利用する
- EXIF orientation（画像の向き情報）を反映する
- 呼び出し側が指定した最大幅・最大高さへ、縦横比を維持して縮小する。拡大はしない
- 背景を白、色空間を sRGB、品質を 94 とした JPEG を出力し、メタデータを削除する
- 出力が実際に JPEG であることを再検査する
- 変換に失敗した場合は例外とし、元ファイルをそのまま保存する fallback（代替処理）は行わない
- 変換後の一時ファイルは block（処理範囲）内だけで利用でき、処理終了時に削除する
- 失敗ログには画像内容、ファイル名、ローカルパスを記録しない
- 入力画像は 60MP 以下かつ縦横それぞれ 16,384px 以下とし、ImageMagick 1処理の上限を30秒、memory 256MiB、map 512MiB、disk 1GiB、thread 2に制限する

### 4.2 添付更新

`ImageAttachments::UpdateService` は、画像変換・保存先へのアップロード・DB transaction（データベースの一連処理）・旧画像削除を一つの更新処理として扱う。

- Record、attachment名、通常属性、アップロード、削除指定、最大幅・最大高さを明示的に受け取る
- JPEGへ正規化した新規Blobを保存先へアップロードし、実在を確認してからDB更新を始める
- DB transaction内で通常属性と添付を保存する
- 呼び出し元固有のDB処理はblockで同じtransactionへ参加できる。ブース初回キャスト紐づけはこのblock内で行う
- DB更新またはblock内処理が失敗した場合はrollbackし、新規Blobをpurgeする
- 差し替え・削除の旧BlobはDB commit後にpurgeする
- 新規アップロードと削除指定が同時にある場合は新規アップロードを優先する
- 画像未変更時は既存Blobの再アップロードや保存先への存在確認を行わない
- 変換・アップロード失敗時は、既存添付とDB上の通常属性を維持する

適用先と保存上限は次のとおりとする。

- `Admin::StoresController#update`: `thumbnail`、1920x1080
- `ProfilesController#update`: `avatar`、1024x1024
- `Cast::BoothsController#update`: `thumbnail_image`、1920x1080
- `Admin::BoothsController#create`: `thumbnail_image`、1920x1080

削除用hidden parameterは各Controllerのstrong parameters（受け付けるパラメータの制限）へ明示し、Controllerからraw `params` を読む共通処理には渡さない。`AttachmentPersistenceChecker` と `RemovableImageAttachment` は上記4経路から外し、現時点ではドリンクアイコン処理だけが利用する。

### 4.3 実行環境

実行環境には HEIC delegate（HEIC 読み取り機能）を含む ImageMagick が必要である。開発用 `Dockerfile` と本番用 `Dockerfile.production` は `imagemagick` をインストールしている。デプロイ候補イメージでは次を実行し、HEIC/HEIF の読み取り対応が表示されることを確認する。

```bash
identify -list format | grep -E 'HEIC|HEIF'
```

ImageMagick 7系で `magick` コマンドを利用する環境では次も確認する。

```bash
magick identify -list format | grep -E 'HEIC|HEIF'
```

形式一覧だけでなく、テスト専用HEICを使って実際にJPEGへ変換できることも確認する。本番画像や利用者がアップロードした画像を確認用fixtureとしてリポジトリへ追加しない。

---

## 5. 削除フラグ

既存画像がある場合、FilePondからファイルを削除すると removeFlag を `1` にする。
新規選択またはファイルが残っている場合は `0` に戻す。

---

## 6. 初期画像

initialUrl がある場合は FilePond に既存画像を追加する。
読み込み失敗時は無視する。

---

## 7. Plugin登録

FilePond plugin は `window.__filepondRegistered` で二重登録を防止する。

利用plugin:

```text
FilePondPluginImagePreview
FilePondPluginImageResize
FilePondPluginImageTransform
```

---

## 8. 設計上の注意点

- FilePondのロードが遅れる可能性があるため、最大40回まで50ms間隔で初期化をリトライする
- allowProcess: false のため、Railsフォーム送信時にファイルとして送る
- HEIC/HEIF変換はブラウザ・FilePond plugin の対応状況に依存する
- サーバー側では申告された `content_type` ではなく画像実体を検査する
