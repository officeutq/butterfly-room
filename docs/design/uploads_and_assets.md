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

native file inputの`accept`には各形式の拡張子とMIME typeを併記し、FilePondの`acceptedFileTypes`は同じ5形式のMIME typeに揃える。拡張子だけではFilePondのtype検証に一致しないため、MIME typeを省略しない。`FilePondPluginFileValidateType`を共通headで読み込み、drag and dropを含む対応外形式はフォーム送信対象から除外し、共通の画面内alertへエラー表示する。ブラウザがHEIC / HEIFのMIME typeを空または`application/octet-stream`として返す場合だけ、拡張子からUI検証用のMIME typeを補完する。ただし、この検証は利用者への早期フィードバックであり、実データ形式の最終判定はサーバー側で行う。

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

### 4.3 OGP用画像variant

ブース共有・配信共有のOGP画像には、`Booth.thumbnail_image` の名前付き `ogp` variant（Active Storageが元画像から生成・再利用する変換画像）を使用する。

- 1200x630px、JPEG、中央基準の `resize_to_fill`、品質85とする
- 元画像は変更せず、添付後に非同期で事前生成する
- 事前生成前に要求された場合は初回アクセス時に生成し、生成済みvariantを以後再利用する
- 共有操作ごとの再変換、SNS別variant、cache bust parameterは設けない
- サムネイル未設定時は、既存ロゴを中央配置した1200x630pxの `booth-share-ogp.jpg` を、ブース単位・配信セッション単位の共有コンテキスト固有URLから無変換で配信する

### 4.4 実行環境

実行環境には HEIC delegate（HEIC 読み取り機能）を含む ImageMagick が必要である。Active Storageのvariant processorは `mini_magick` とし、アップロード正規化とvariant生成で同じImageMagick実行環境を利用する。開発用 `Dockerfile` と本番用 `Dockerfile.production` は `imagemagick` をインストールしている。デプロイ候補イメージでは次を実行し、HEIC/HEIF の読み取り対応が表示されることを確認する。

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
初期画像の読込失敗や、cache bust再試行のためにFilePond内部の項目を取り除く場合は、removeFlagを変更しない。

---

## 6. 初期画像

initialUrl がある場合は FilePond に既存画像を追加する。
初回の読込に失敗した場合だけ、同じURLへcache bust parameterを付けて1回再試行する。これは既存の初期画像取得失敗対策を維持するもので、無制限には再試行しない。再試行も失敗した場合は既存添付を削除扱いにせず、removeFlagを`0`のまま維持する。

Turbo遷移などでControllerがdisconnectした場合は、初期化timerを停止し、作成済みFilePondを破棄する。disconnect後は初期画像の再試行結果を画面状態へ反映しない。

---

## 7. Plugin登録

FilePond plugin は `window.__filepondRegistered` で二重登録を防止する。

利用plugin:

```text
FilePondPluginImagePreview
FilePondPluginImageResize
FilePondPluginImageTransform
FilePondPluginFileValidateType
```

FilePond本体と上記4pluginがすべて読み込まれるまで、50ms間隔で最大40回初期化を再試行する。一部pluginが未読込の状態では登録済み扱いにしない。

---

## 8. 設計上の注意点

- FilePondのロードが遅れる可能性があるため、最大40回まで50ms間隔で初期化をリトライする
- allowProcess: false のため、Railsフォーム送信時にファイルとして送る
- HEIC/HEIF変換はブラウザ・FilePond plugin の対応状況に依存する
- ブラウザがHEIC/HEIFをプレビュー・変換できない場合も選択を許可し、サーバー側でJPEGへ正規化する旨をStore / Booth / Userで共通表示する
- 対応外形式はFilePondで送信前にエラー表示する
- サーバー側では申告された `content_type` ではなく画像実体を検査する

JavaScriptのlifecycle、初期画像再試行、削除フラグ、plugin登録は次で確認する。

```bash
npm run test:js
```

---

## 9. 保存済み画像の棚卸し

本番へ保存済みのStore thumbnail、Booth thumbnail_image、User avatarは、`ImageAttachments::InventoryService`を利用するdry-runタスクで棚卸しする。

- 標準実行はHEIC / HEIF拡張子または対象Content-Typeを持つDBメタデータ候補だけを実体検査する
- 保存先オブジェクトの存在、実体形式、JPEG変換可否を確認する
- 全件実体検査は保存先ダウンロードと画像変換を伴うため、件数上限を必須とする
- 棚卸し処理ではBlob、Attachment、対象Record、S3オブジェクトを更新・削除しない
- S3キーを直接上書きせず、是正時は`ImageAttachments::RemediateService`から`ImageAttachments::UpdateService`を再利用して新規JPEGを再添付する
- 是正は1件単位とし、棚卸し時のattachment ID・blob IDをrecordロック内で再照合する
- 競合時は新しい添付を上書きせず、補正済みの正常なJPEGへ再実行した場合はスキップする
- 旧Blobの削除は新JPEGのアップロード・添付・実体確認が成功し、transactionが完了した後に非同期で行う

実行方法と結果statusは`docs/ops/image_attachment_remediation.md`を参照する。

---

## 10. Cropper.js移行の検証画面

FilePondからCropper.jsへ移行する前段として、`/system_admin/image_upload_verification` に保存を伴わない検証画面を置く。通常は無効で、環境変数 `IMAGE_UPLOAD_VERIFICATION_ENABLED=1` を設定した場合だけsystem_adminのダッシュボードに導線を表示し、直接アクセスも許可する。無効時の直接アクセスは404とする。

- Cropper.js 2.2.0を利用する
- アバターは1:1、ヒーロー・カードは40:21（1200x630）の固定選択枠とする
- 選択枠は移動・リサイズさせず、編集元画像を移動・拡大縮小する
- 縮小の下限は編集エリア全体ではなく、選択枠を埋める最小倍率とする。下限をまたぐ操作は最小倍率で止め、端に寄せた状態でも余白が生じない位置へ補正する
- 回転・反転は提供せず、画像が選択枠内で余白を作らないようにする
- クロップ状態はCropper.js固有の変換行列ではなく、編集元画像上の`x`、`y`、`width`、`height`と編集元画像サイズでJSON化する
- Cropper.jsのサブピクセル丸めでクロップ座標が編集元画像から1出力ピクセル未満はみ出す場合は、幅・高さとアスペクト比を変えずに画像内へ正規化する
- JSONから同じクロップ状態を復元できることを確認する
- 表示用画像はアバター1024x1024、ヒーロー・カード1200x630のJPEGとしてブラウザ内だけで生成する
- 透過画像のJPEG出力背景は白、品質は0.9とする
- 選択した画像、クロップ状態、生成JPEGはサーバーへ送信・保存しない
- Turbo cacheへの保存前とStimulusのdisconnect時にCropper、event listener、Object URLを破棄する

この検証画面が受け付ける形式はJPEG / PNG / WebPまでとする。HEIC / HEIFのブラウザ変換、Active Storage保存、既存画像移行は後続検証・実装で追加し、現行のFilePond経路にはこの段階で影響させない。

縮小下限・状態復元・JPEG出力を実際のCropper.jsとChromiumで確認する場合は、既存のPlaywright用Chromiumを利用して次を実行する。Railsやログインは不要で、テスト専用の画像を使う。

```bash
node --test test/javascript/browser/image_upload_verification_zoom_test.cjs
```
