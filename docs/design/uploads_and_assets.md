# Uploads / Assets 設計

> 1〜9節はStore / Boothと移行中の互換処理に残るFilePond経路、10〜14節は検証記録である。Userプロフィールは#1156からCropper.js経路を利用する。検証結果から確定したCropper.js移行仕様は [Cropper.js画像アップロード確定設計](image_upload_cropper_architecture.md) を正とする。

## 1. 概要

Store / Booth画像はFilePond経路を利用する。Userプロフィールのavatar / coverは共通Cropper.js部品で固定比率編集し、HEIC / HEIFを含む入力からブラウザで編集元・表示用JPEGを生成してRails multipartで保存する。どちらの経路もブラウザの申告だけを保存可否の根拠にせず、Rails側で画像実体を再検査する。

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
- `ProfilesController#update`: 旧方式互換の`avatar`、1024x1024。通常プロフィール画面は新方式の`avatar_image_pair` / `cover_image_pair`を利用する
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

User公開プロフィールのOGP画像には、Cropper.jsで生成・保存した1200x630pxの`cover_image`を再変換せず使用する。`cover_image`未設定時はカード・プロフィールのヒーロー領域と同じ共通ロゴ`no_image_logo.png`へフォールバックする。小型アイコン用の`avatar`や再編集用の`cover_image_source`はOGPへ使用しない。

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

FilePondからCropper.jsへ移行する前段として、`/system_admin/image_upload_verification` に検証画面を置く。通常は無効で、環境変数 `IMAGE_UPLOAD_VERIFICATION_ENABLED=1` を設定した場合だけsystem_adminのダッシュボードに導線を表示し、直接アクセスも許可する。無効時の直接アクセスは404とする。#1132から、明示操作による一時保存の検証を追加した（13節参照）。

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
- 画像の選択・クロップ操作だけでは送信しない。「2画像を一時保存して検証」を押した場合だけ、編集元JPEG・表示用JPEG・クロップ情報を検証専用領域へ送信する
- Turbo cacheへの保存前とStimulusのdisconnect時にCropper、event listener、Object URLを破棄する

当初の検証対象はJPEG / PNG / WebP。#1131でHEIC / HEIFのブラウザJPEG変換を追加した（12節参照）。#1132のActive Storage保存は一時検証だけで、本番添付・既存画像移行は未実装。現行のFilePond経路には影響させない。

#1150で、検証画面から固定比率・最小倍率・端補正・crop data復元を `image_attachments/cropper_editor.js` へ分離し、通常画面向けの `image_attachment_editor_controller` と共通partialを追加した。#1152でHEIC / HEIF変換を `image_attachments/heic_converter.js` と独立Workerへ移し、通常UIはWorker・3200万画素上限に固定した。JPEG / PNG / WebPではdecoderを読み込まず、HEIC / HEIFはフルサイズJPEGへ変換してから共通正規化へ渡す。共通partialは5節の現行FilePond入力とは別で、個別フォームへ接続する後続Issueまでは通常経路に表示しない。

縮小下限・状態復元・JPEG出力を実際のCropper.jsとChromiumで確認する場合は、既存のPlaywright用Chromiumを利用して次を実行する。Railsやログインは不要で、テスト専用の画像を使う。

```bash
node --test test/javascript/browser/image_upload_verification_zoom_test.cjs
node --test test/javascript/browser/image_attachment_editor_test.cjs
```

## 11. 編集元JPEGの正規化検証（#1130）

10節の検証画面を拡張し、入力を未クロップの編集元JPEGへ変換してからCropper.jsへ渡した。以下には#1130時点の比較記録も含むが、#1134で採用値を確定し、#1154で `image_attachments/source_normalizer.js` を通常画面向けの共通module（再利用可能な処理単位）として分離した。現行FilePond・Active Storage・`ImageAttachments::UpdateService` の経路にはまだ接続しない。

### 正規化手順

1. ファイル容量とJPEG / PNG / WebPの実体ヘッダーを確認し、デコード前に寸法・画素数・縦横比を検査する。拡張子・申告MIMEだけを信用せず、確認したMIMEで読み込む。アニメーションPNG / WebPはこの検証では対象外とする。
2. `createImageBitmap` の `imageOrientation: "from-image"` でEXIFの向きを反映する。`InvalidStateError`、またはAPI非対応時だけ `HTMLImageElement.decode()` へ切り替える。向きはブラウザの読み込みで反映させ、手動の追加回転は行わない。読み込んだ実寸法も再検査する。
3. 用途の必要寸法を満たすように全体を等比拡大し、大きい場合は選択した上限へ等比縮小する。切り抜き・余白追加は行わない。
4. sRGBのCanvas（描画領域）を白で塗り、`imageSmoothingQuality: "high"` で全体を描画する。品質0.94のJPEGとして再生成し、元EXIF / GPSは引き継がない。
5. 生成した同じJPEGを編集元プレビュー・ダウンロード・Cropper.jsへ渡す。クロップJSONの `source` はこのJPEGの寸法とする。表示用JPEGは従来どおり品質0.90、1024×1024または1200×630。

向き・色空間のAPI仕様は [HTML Standard: ImageBitmap](https://html.spec.whatwg.org/multipage/imagebitmap-and-animations.html#imagebitmap) と [Canvas](https://html.spec.whatwg.org/multipage/canvas.html) を参照。WebPの実体確認は [WebP Container Specification](https://developers.google.com/speed/webp/docs/riff_container) に基づく。

### 拡大・縮小と採用上限

入力寸法は向き補正後の `w, h` とする。

```text
requiredScale = max(用途の横幅 / w, 用途の高さ / h)
maximumScale = min(最大辺 / w, 最大辺 / h, sqrt(最大画素数 / (w * h)))
scale = min(max(1, requiredScale), maximumScale)
```

`requiredScale > maximumScale` は、最低寸法と上限を両立できないためエラーとする。整数化は上限を超えないよう切り捨て、用途の最低寸法を下回らないよう補正する。縦横比の差は整数化による1px未満に限る。

| 項目 | 採用値 | 位置づけ |
| --- | --- | --- |
| 入力容量 | 20MiB以下 | デコード前に拒否 |
| 入力寸法 | 長辺8192px・3200万画素以下 | ヘッダーとデコード後の両方で検査 |
| 入力縦横比 | 長辺/短辺が8以下 | 用途・出力上限との両立条件でも制限される |
| 編集元 | 長辺4096px・800万画素以下 | 以後のCropper・再編集の負荷を抑える固定上限 |
| 編集元JPEG品質 | 0.94 | 通常画面向けAPIでは変更不可 |

例えば320×180の入力はアバター用1820×1024、ヒーロー・カード用1200×675となる。6000×4000は3464×2309へ縮小する。100×800の入力はヒーロー・カード用に最低1200×9600が必要になり、編集元上限と両立しないためエラーとなる。#1130で比較した元寸法維持mode（動作設定）は、通常画面向けAPIと現在の検証画面から撤去した。

低解像度画像は拡大倍率と「細部の解像感は増えない」旨を警告表示するが、処理は妨げない。大きい画像の縮小も通知する。

### 状態・解放・失敗時の扱い

- 用途変更・処理再試行は、最初に選択した入力ファイルから再変換してクロップを初期化する。生成JPEGの再圧縮を繰り返さない。品質と上限は共通module内の固定値とする。
- JSON復元は同じ用途・編集元寸法に限定する。この検証のJSONは画像識別子を含まないため、別画像の同寸法JSONは識別できない。本番保存時の画像との関連付けは後続Issueで扱う。
- 共通の `ImageSourceNormalizer` が変換を世代番号で直列化し、連続した変更では最後の結果だけを返す。ブラウザ内部で進行中のデコード・エンコード自体は中断できないため、その完了後に不要な結果を破棄する。通常画面のControllerは `cancel()` / `dispose()` をlifecycle（初期化から破棄までの流れ）に合わせて呼ぶ。
- ImageBitmap、フォールバック画像のURL、一時Canvas、編集元・表示用URLを解放する。Turbo遷移・disconnect時には入力ファイルの参照も破棄する。
- 破損画像、上限超過、描画領域確保失敗、JPEG生成失敗はコード付きエラーとして返し、状態欄へ表示する。拡大・縮小はコード付き警告として返す。失敗した新画像を古い編集元・ダウンロードと混同しないよう表示を空にし、別画像で再試行できる。
- ヘッダー検査は完全なセキュリティ検証ではない。本番移行時のサーバー検証は引き続き必要。上限内でも低メモリ端末のタブ終了を完全には防げず、タブ終了はJavaScriptから捕捉できない。

### 再現可能な検証

```bash
npm run test:js
node --test test/javascript/browser/image_source_normalization_test.cjs
node --test test/javascript/browser/image_upload_verification_zoom_test.cjs
```

ブラウザ検証は既存のPlaywright（ブラウザ自動テスト）を使い、ログイン・DB・サーバー保存なしで実コードを実行する。初回は `npx playwright install chromium firefox webkit` で検証用ブラウザを用意する。既定はChromium。他のエンジンはPowerShellで以下のように指定する。

```powershell
$env:IMAGE_VERIFICATION_BROWSER = "firefox" # または webkit
node --test test/javascript/browser/image_source_normalization_test.cjs
node --test test/javascript/browser/image_upload_verification_zoom_test.cjs
Remove-Item Env:IMAGE_VERIFICATION_BROWSER
```

テスト内に4色・透過・EXIF全8方向とGPS情報・文字/細かい模様・大きい画像の生成手順を保持する。入出力サンプルを毎回生成し、固定品質・固定上限、出力の寸法・4領域の色・JPEGのAPP1セグメント除去・エラー後再試行を検証する。共通moduleは検証専用の処理時間・比較設定を公開APIに含めない。手元の画像は検証画面の「編集元JPEGをダウンロード」と正規化結果JSONから確認・記録できる。

2026-09-02、Windows上のPlaywrightによるChromium 149.0.7827.55、Firefox 151.0、WebKit 26.5で、3形式の変換・向き・透過・EXIF/GPS除去、およびCropperの縮小下限・JSON復元・設定連続変更・離脱・エラー後再試行が通過した。FirefoxではEXIF付きJPEGの `createImageBitmap` が失敗し、`HTMLImageElement` への切り替えで全8方向を確認した。**Windows WebKitの結果はiPhone Safari実機の結果ではない。**

測定例（各エンジン内で同じ1000×700の文字/模様PNGを使い、1200×840へ拡大。容量はbyte / 時間はms）:

| エンジン | 品質0.90 | 品質0.94 | 品質0.98 |
| --- | --- | --- | --- |
| Chromium | 344716 / 1038.8 | 451924 / 1061.0 | 698963 / 1057.9 |
| Firefox | 546323 / 15 | 730989 / 16 | 1215080 / 17 |
| WebKit | 367363 / 76 | 481221 / 81 | 738347 / 85 |

大きい6000×4000 JPEGの測定例（品質0.94）:

| エンジン | 入力容量 | 既定3464×2309：容量 / 時間 | 元寸法維持：容量 / 時間 |
| --- | --- | --- | --- |
| Chromium | 1487654 | 740869 / 1233.8 | 1526581 / 1210.4 |
| Firefox | 2338129 | 1219901 / 131 | 2356536 / 197 |
| WebKit | 1449322 | 758372 / 536 | 1438714 / 469 |

これらは#1130検証時の単発の経過時間で、ファイル読み込み・ブラウザの処理待ちを含む。特にChromiumの独立ページの計測には約1秒のエンコード待ちが含まれた。入力生成自体も各ブラウザのCanvasで行うため、圧縮や文字描画の差があり、エンジン間の速度順位・同一画質を保証するベンチマークではない。

0.98は模様サンプルで0.94比約1.5〜1.7倍の容量となった。全解像度保持は大きい画像の再編集メモリを増やす。画質の目視確認とiPhone 15 Proでの12MP / 24MP確認を踏まえ、#1134で編集元0.94・表示用0.90・編集元800万画素を採用した。

ユーザーにより、小さい写真・透過PNGでの画質低下は想定内として確認済み。広色域/ICCプロファイル画像の色差、Android Chrome、実端末の最大メモリ等は検証時点で未確認だった。HEIC配布条件は#1152、通常フォームの実機確認は#1153へ引き継いだ。入力20MiBの制限が、生成後JPEGの容量上限を保証するものではない。

## 12. HEIC / HEIFブラウザ変換の検証（#1131）

検証画面で、HEIC / HEIF → フルサイズJPEG → 11節の編集元正規化 → Cropper.jsの順に処理を検証した。#1152で同じ変換を通常フォーム向け共通moduleへ移し、共通partialからライセンス・ソース情報へ到達できるようにした。Worker（画面操作と分離した処理）の比較、中止、変換測定は検証画面に残す。選定理由・上限・PC自動テスト結果・未実施の実機チェックは [heic_verification.md](heic_verification.md) に集約する。

HEIC入力は標準16MPを維持し、Worker専用の32MP比較を明示選択できる。これは24MP写真を試す高負荷な検証設定であり、本番上限の決定ではない。容量20MiB・長辺8192px・縦横比8:1・30秒制限・後続の既定800万画素への正規化は維持する。画面を開き直すと標準へ戻り、メインスレッド比較は常に4MPまで。JSONに実行した上限を記録する。

通常経路もHEIC選択時だけ共通Workerを利用する。#1155でプロフィール保存側はavatar / coverの新方式画像組と通常属性を一体更新できるようにし、#1156でプロフィールViewをCropper.jsへ切り替えた。既存`ImageAttachments::UpdateService`経路は撤去Issueまでサーバー互換として排他的に維持する。実機横断確認は#1153を#1134の確定設計に対する本番公開gateとする。

## 13. 2画像の送信方式・一時保存検証（#1132）

共通検証ページにmultipart（Rails経由の一括送信）とActive Storage direct upload（ブラウザから保存先への直接送信）の比較を追加する。両方式で同じ開始時点のクロップを生成し、実体検査後の測定JSONを表示する。通常の画像添付は更新しない。仕様・清掃・デプロイ前提・検証結果・未確定事項は [image_upload_transport_verification.md](image_upload_transport_verification.md) を正とする。

## 14. 2画像の一体更新・既存画像移行の試作（#1133）

本番モデルを変更せず、事前アップロード済みsource/displayとcrop dataの一体更新、期待attachment/blob IDによる競合拒否、失敗時清掃を試作した。既存表示Blobから独立した編集元JPEGと中央クロップ画像を生成し、低解像度時の最低寸法への拡大、dry-run、再開・冪等性の移行方針も確認した。Service分割・失敗状態・移行順序・残課題は [image_attachment_pair_and_migration_prototype.md](image_attachment_pair_and_migration_prototype.md) を正とする。

## 15. 検証後の採用仕様（#1134）

#1129〜#1133を統合し、初期送信はRails multipart、編集元は品質0.94・長辺4096px・800万画素以下、入力は20MiB・長辺8192px・3200万画素・縦横比8:1以下とする。User / Store / Boothは用途ごとに編集元Blob・固定寸法の表示用Blob・schema version 1のcrop dataを保持する。

添付名、通常更新、競合・清掃、段階的な既存画像移行、ステージング検証、本番移行、FilePond・検証機能の撤去条件を含む確定内容は [image_upload_cropper_architecture.md](image_upload_cropper_architecture.md) を参照する。検証文書中の「候補」「未決定」は各検証時点の記録として残し、最終判断は確定設計を優先する。
