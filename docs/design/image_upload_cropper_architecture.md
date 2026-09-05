# Cropper.js画像アップロード確定設計

更新: 2026-09-04。大Epic #1127、検証Epic #1128、設計確定Issue #1134。

## 1. 本書の位置づけ

本書は、#1129〜#1133の検証結果から確定した新方式の実装目標を定義する。現在の本番経路は実装用Issueが完了するまでFilePondを利用するため、現行仕様と移行後仕様を混同しない。

新方式は、1用途につき次の3点を一つの画像組として管理する。

- ブラウザで向き・色・背景・寸法を正規化した未クロップJPEGである編集元画像
- 固定比率でクロップした表示用JPEG
- 編集元画像上のクロップ座標等を持つcrop data

HEIC / HEIFファイルそのものは保存しない。既存画像の移行完了、通常経路の確認、本番データ確認後にFilePondと検証専用機能を撤去する。

## 2. 確定事項

| 項目 | 採用内容 |
| --- | --- |
| 画像編集 | Cropper.js 2.2.0、npmで完全固定、既存Importmapから読み込む |
| 操作 | 固定選択枠に対する画像の移動・拡大縮小。回転・反転・自由比率は提供しない |
| 用途 | avatarは1:1・1024×1024、cover / store / boothは40:21・1200×630 |
| 入力形式 | JPEG / PNG / WebP / HEIC / HEIF |
| 編集元 | 未クロップJPEG、品質0.94、sRGB、透過は白背景、EXIF / GPS等を引き継がない |
| 表示用 | JPEG、品質0.90、用途ごとの固定寸法 |
| 小さい画像 | 用途の必要寸法まで等比拡大し、画質低下の警告は出すが保存を妨げない |
| 大きい画像 | 編集元を長辺4096px・800万画素以下へ等比縮小する |
| 入力上限 | 20MiB、長辺8192px、3200万画素、長辺/短辺8以下 |
| 送信 | Rails multipartで編集元・表示用を同じフォーム送信に含める |
| 保存 | Active Storage。用途ごとに編集元と表示用を別Blob・別キーで保持する |
| 再編集 | 既存編集元を読み込みcrop dataを復元し、表示用とcrop dataだけを更新する |
| 差し替え | 編集元・表示用・crop dataをすべて更新する |
| 削除 | 用途単位で編集元・表示用・crop dataをすべて削除する |
| 既存画像 | 用途ごとに物理複製し、中央クロップで初期表示用画像とcrop dataを作る |

Active Storage direct uploadは初期実装に採用しない。iPhone 15 Proの同一約3.96MB画像ではdirect 1,859ms、multipart 4,083msだったが、当面の同時接続数、実装・運用・失敗状態の単純さを優先する。保存Serviceは送信方式に依存させず、利用増加や実測悪化時にdirectへ切り替えられる境界を維持する。

## 3. 用途別の保存契約

| 対象 | 編集元添付 | 表示用添付 | crop data | 比率・出力 |
| --- | --- | --- | --- | --- |
| Userアバター | `avatar_source` | `avatar` | `avatar_crop_data` | 1:1、1024×1024 |
| Userカバー | `cover_image_source` | `cover_image` | `cover_image_crop_data` | 40:21、1200×630 |
| Store | `thumbnail_source` | `thumbnail` | `thumbnail_crop_data` | 40:21、1200×630 |
| Booth | `thumbnail_image_source` | `thumbnail_image` | `thumbnail_image_crop_data` | 40:21、1200×630 |

表示用添付は既存名を維持し、公開画面の参照変更を抑える。Userカバーだけは新規追加する。公開・管理カード、選択画面、ヒーロー、待機画面、OGPは40:21の表示用添付を利用し、編集元を公開表示に使わない。新方式のBooth OGPは検査済み表示用JPEGを無変換で配信し、旧画像だけ移行完了まで互換variantを利用する。Store / BoothのOGP未設定時は1200×630の共通JPEGへフォールバックする。

crop dataはJSONBで保存し、schema version 1を次の形で扱う。

```json
{
  "schemaVersion": 1,
  "ratioKey": "social",
  "sourceBlobId": 123,
  "source": { "width": 3265, "height": 2449 },
  "crop": { "x": 220.41, "y": 628.41, "width": 2008.18, "height": 1054.29 },
  "zoom": 1.6257,
  "output": {
    "width": 1200,
    "height": 630,
    "mimeType": "image/jpeg",
    "quality": 0.9
  }
}
```

`crop`は編集元画像上のピクセル座標とし、Cropper.js固有のDOM座標や変換行列は保存しない。復元時はschema version、用途、出力、`sourceBlobId`、編集元の実寸法、範囲、比率、zoomを再検証する。一致しない情報を別画像へ適用せず、再クロップを求める。

## 4. ブラウザ処理

### 4.1 共通処理

1. 拡張子や申告MIMEだけでなく実体ヘッダーを確認する。
2. デコード前後に容量・寸法・画素数・縦横比を検査する。
3. EXIF方向を一度だけ反映する。`createImageBitmap`が失敗・非対応の場合は`HTMLImageElement.decode()`へ切り替える。
4. 用途の最低寸法を満たす倍率と、長辺4096px・800万画素の上限を両立させる。両立しない極端な画像は拒否する。
5. sRGB Canvasを白で塗り、画像全体を高品質リサイズして品質0.94の編集元JPEGを生成する。
6. 編集元JPEGをCropper.jsへ渡し、品質0.90の表示用JPEGを生成する。

1〜5は `image_attachments/source_normalizer.js` の `ImageSourceNormalizer` に集約する。`normalize(file, { ratioKey })` は固定仕様で編集元JPEG、入力・向き補正後・編集元の情報、拡大・縮小警告を返し、失敗時はコード付きエラーを返す。品質や処理上限、検証用の計測modeを呼び出し側から変更させない。

6の固定比率編集、編集元座標とCropper.js変換の相互変換、最小倍率・端補正、schema version 1の検査は `image_attachments/cropper_editor.js` に集約する。通常フォームは `shared/_image_attachment_editor.html.erb` を描画し、`image_attachment_editor_controller` が現在の編集元・表示用・crop data・期待IDと、生成したmultipart file inputを管理する。個別フォームは `square` / `social` の用途と現在状態を渡し、Cropper.js固有の変換行列やDOM座標を永続parameterに含めない。

構図の確定までは通常フォームの送信対象を更新せず、編集中の通常フォーム送信を拒否する。確定後は `replace` / `reedit` / `delete` と必要な画像だけを5節の契約へ設定し、取消時は編集開始時の表示と空の操作へ戻す。保存の成否は親フォームが扱う。

入力変更、用途変更、処理再試行は最初の入力ファイルから行い、生成JPEGを繰り返し再圧縮しない。共通moduleが処理を世代番号で直列化し、古い非同期結果を反映しない。Turboキャッシュ前とStimulusの`disconnect`で `cancel()` / `dispose()` を呼び、Cropper、Worker、ImageBitmap、Object URL、event listenerを解放する。

### 4.2 HEIC / HEIF

`heic-to` 1.5.2に含まれるlibheif 1.22.2のCSP対応decoderを技術実装として採用し、アプリが所有する独立module Workerから必要時だけ読み込む。高水準APIの非公開Workerには依存しない。先頭静止画像だけを利用し、生のHEIC / HEIFやサーバー変換へ黙って切り替えない。

24MPのiPhone写真を受け付けるため、Workerは3200万画素までとする。入力20MiB、長辺8192px、縦横比8:1、静止画像20個、処理30秒を上限とする。48MP等の上限超過、破損、対応外codec、Worker起動失敗、メモリ不足は保存へ進めず、再選択できるエラーを表示する。

`image_attachments/heic_converter.js` の `ImageHeicConverter` を通常UIとdecoderの境界とし、通常UIは低水準APIや配布ファイルの内部パスに依存させない。通常経路はWorker・3200万画素上限に固定し、検証画面だけが16MP / 32MPとメインスレッド比較を選べる。JPEG / PNG / WebP選択時はWorkerとdecoderを読み込まない。

LGPL-3.0-or-laterの告知、対応ソース・ビルド情報、配布物checksum、置換可能性は `/licenses/heic-verification.txt` に記録し、通常の画像編集UIから到達可能にする。これは採用版と対応ソースを識別する技術対応であり、法的適合を保証しない。条件を満たせない場合は、同じブラウザ変換インターフェースを保ったままdecoderを差し替える。

## 5. Rails・Active Storage処理

Controller（リクエストを受ける層）は認可、strong parameters、通常属性の受領、共通Service（業務処理を集約するクラス）呼出し、レスポンスに留める。画像の実体検査、Blob作成、transaction（データベースの一連処理）、競合検知、清掃はServiceへ集約する。

- 編集元は20MiB以下、表示用は5MiB以下、multipart全体は26MiB以下とする。
- 両画像をJPEG実体として再検査し、寸法、crop dataとの一致、表示用の固定寸法を確認する。
- Railsで受信した一時ファイルからBlobを事前作成し、保存先に実体が存在することを確認してから短いDB transactionを開始する。
- 編集開始時のsource/display attachment ID・blob IDを保存時にレコードロック下で再照合する。古いタブや移行後の上書きは409相当の再編集要求にする。
- 新規・差し替えは2添付とcrop data、再編集は表示用添付とcrop data、削除は2添付とcrop dataを一つのtransactionで更新する。
- 同じレコードの複数用途を一回のフォーム送信で更新する場合は、全用途を検査・事前保存した後、通常属性を含めて一つのtransactionでcommitする。一用途の競合・検証・保存失敗でも他用途を含む更新全体をrollbackし、今回事前保存したBlobを清掃する。
- transaction失敗時は旧状態を維持し、新規Blobだけを同期清掃する。成功後に参照されなくなった旧Blobを非同期清掃する。別添付から参照されるBlobは削除しない。
- DBとS3は同一transactionにできないため、プロセス強制終了時に残った本機能所有の未添付Blobを期限付き清掃できる識別情報を持たせる。

事前保存するBlobのmetadataには`image_attachment_staging`を付け、`schemaVersion`、用途、`source` / `display`の役割、`cleanupAfter`を記録する。既定の清掃期限は作成から1時間とし、画像組のcommit時に同じtransaction内で印を外す。5分ごとの定期Jobは、期限を過ぎ、専用metadataが正しく、どこにも添付されていないBlobだけを清掃する。保存先の削除後にBlob行を削除し、保存先削除に失敗した場合は行とmetadataを残して次回再試行できるようにする。

通常フォームは1用途につき、既定では`image_pair`を次のmultipart parameter契約で送る。Userのavatar / coverのように同じフォームで複数用途を扱う場合は、用途別のroot名をControllerから`MultipartPayload.from_params`へ指定し、配下は同じ契約を使う。`crop_data`はJSON文字列、`expected`は編集画面を開いた時点のIDとし、画像未設定時は4項目を空文字で送る。Controllerはstrong parametersと値検査を共通化した結果を`ImageAttachments::MultipartUpdateService`へ渡す。

Userプロフィールでは`avatar_image_pair`と`cover_image_pair`を用途別rootとし、`Profiles::UpdateService`が通常属性と両用途を一体更新する。通常Viewは既存FilePond用`user[avatar]` / `user[remove_avatar]`を送信しない。サーバー互換は撤去Issueまで維持するが、新方式rootとの同時送信は画面再読み込みを求めて拒否する。

Store管理フォームでは既定rootの`image_pair`を利用し、`Stores::UpdateService`が通常属性と`thumbnail`画像組を一体更新する。通常Viewは既存FilePond用`store[thumbnail]` / `store[remove_thumbnail]`を送信しない。サーバー互換は撤去Issueまで維持するが、新旧parameterを同時送信した場合は二重処理せず拒否する。

Booth作成・編集フォームも既定rootの`image_pair`を利用し、`Booths::UpdateService`が通常属性、`thumbnail_image`画像組、初回キャスト紐づけを一つのtransactionで更新する。通常Viewは既存FilePond用`booth[thumbnail_image]` / `booth[remove_thumbnail_image]`を送信しない。サーバー互換は撤去Issueまで維持するが、新旧parameterを同時送信した場合は二重処理せず拒否する。

```text
image_pair[operation] = replace | reedit | delete
image_pair[source] = 編集元JPEG（replaceだけ）
image_pair[display] = 表示用JPEG（replace / reedit）
image_pair[crop_data] = schema version 1のJSON文字列（replace / reedit）
image_pair[expected][source_attachment_id]
image_pair[expected][source_blob_id]
image_pair[expected][display_attachment_id]
image_pair[expected][display_blob_id]
```

multipart全体の26MiB上限はPumaでRails到達前に適用し、同じ上限のRack middlewareでも`Content-Length`の超過・欠落・虚偽を検知する。middlewareはmultipartだけを対象とし、413では`image_pair_request_too_large`と`retryable: true`を返す。Pumaの上限はサーバー全体のbodyに作用するため、新方式以外も26MiBを超える必要がないことを維持する。個別画像は`PairValidator`でsource 20MiB、display 5MiBをBlob作成前に検査する。

ブラウザ送信には`ImagePairMultipartClient`を使い、待ち時間を45秒で打ち切って手動再送可能に戻す。自動再送は行わない。通信中断・タイムアウト後もサーバー側が完了する可能性があるため、再送時も元の`expected`を使う。先行送信が完了済みなら後着送信を競合として拒否し、後着側の一時Blobだけを清掃する。

Userプロフィール、Store管理、Booth作成・編集フォームではフォーム単位の`image_pair_form_controller`が確定済みpayloadと通常属性を一つの`FormData`として送る。いずれかが編集中・生成中なら送信せず、失敗時は生成済みFileと期待IDを保持して手動再送できる状態へ戻す。成功時だけRailsが返した同一originの遷移先へ移動する。送信ボタンに確認文がある場合はXHR送信前にも確認する。既存編集元はS3のCORS変更を前提にせず、署名済みActive Storage proxy URLから同一originで読み込む。

ALBの無通信タイムアウト60秒とS3設定は初期実装で変更しない。クライアント側の画像送信待ちは45秒を上限とし、超過時は再送可能な状態へ戻す。ステージングで20MiB境界と低速条件を確認し、既存60秒内に収まらない場合だけインフラ変更を別途判断する。

既存 `ImageAttachments::UpdateService` は移行期間中のFilePond経路と、単一添付をサーバー正規化する経路のために維持する。新方式はブラウザ生成済みの2画像を再圧縮しないため、試作した `StagedPairUpdateService` を本番契約へ仕上げ、責務を混在させない。

## 6. 通常操作

### 新規・差し替え

1. 入力ファイルから編集元JPEGを生成する。
2. 固定比率で構図を決め、表示用JPEGとcrop dataを生成する。
3. 通常属性と2画像をRails multipartで送る。
4. サーバー検査後、2添付・crop data・必要な通常属性を一体更新する。

### 再編集

1. `sourceBlobId`と一致する既存編集元をCropper.jsへ読み込む。
2. 保存済みcrop dataを検証して初期構図へ復元する。
3. 新しい表示用JPEGとcrop dataだけを送る。
4. 編集元Blobを変更せず一体更新する。

### 削除

削除確認後、用途の編集元・表示用・crop dataをまとめて削除する。新画像の選択キャンセル、初期画像の読込失敗、画面離脱を削除操作として扱わない。

## 7. 既存画像移行

移行バッチはモデル・通常UIの実装後に追加し、用途単位・attachment ID順で1件ずつ処理する。既存表示Blobを参照元として保持するのではなく、新しい編集元Blobへ物理複製する。必要な場合は向き補正・白背景・sRGB・品質0.94のJPEGへ変換し、通常経路と同じ編集元上限を適用する。

- Userの既存`avatar`から、アバター用とカバー用を別々に生成する。2用途の生成元はどちらも移行前の`avatar`とする。
- Storeの`thumbnail`、Boothの`thumbnail_image`から、それぞれ編集元・中央クロップ表示用・crop dataを生成する。
- source/display/crop dataがすべて揃い、用途・寸法・`sourceBlobId`が一致する場合だけ移行済みとしてスキップする。部分状態は成功扱いにしない。
- dry-run、明示ID範囲、件数上限、`after_attachment_id`による再開、期待attachment/blob IDによる競合拒否を必須とする。
- JSON Linesログには種別、レコードID、attachment/blob ID、用途、寸法、結果だけを記録し、S3キー、署名URL、画像、個人情報を記録しない。
- 欠損、破損、上限超過、競合、アップロード失敗、保存失敗を別statusにし、失敗対象だけ再確認できるようにする。
- 詳細なJSON Linesはアクセスを制限して本番移行の事後確認完了から90日保持し、未解決対象が個別Issueへ転記済みであることを確認して削除する。件数・status・実行commit・期間の要約は運用記録へ残す。

実装は`ImageAttachments::LegacyMigrationService`と`image_attachments:migrate_legacy_pairs`へ集約する。Userはcoverを先に確定してからavatarを別transactionで確定し、cover失敗時は移行前avatarを維持する。既に新方式avatarへ更新済みでcover未設定のUserにはcoverを自動生成しない。実行変数、guard、JSON Linesの保管と照合は[既存画像を新方式へ移行する運用手順](../ops/legacy_image_pair_migration.md)を正とする。

実行は必ず次の順とし、各段階を別の運用Issueで記録する。

1. ステージングdry-run
2. ステージング少数件移行と新方式での再編集・差し替え・削除確認
3. ステージング全件移行と件数・実体・公開表示確認
4. 本番dry-runと実行対象・失敗一覧の承認
5. 本番移行と事後照合

ローカル自動テストやDiskサービスでの試作だけを、ステージング移行確認済みとは扱わない。

## 8. 検証・リリース条件

実装PRごとに関連Rails / JavaScriptテスト、実ブラウザテスト、RuboCop、Zeitwerk、Brakeman、CSS buildを変更範囲に応じて実行する。公開前に最低限次をステージングで確認する。

- User / Store / Boothの新規、再編集、差し替え、キャンセル、削除
- JPEG / PNG / WebPと、iPhone Safariの12MP・24MP HEIC
- avatar / social両用途の指移動、ピンチ、縮小下限、画面回転、crop復元
- Android ChromeでJPEG / PNG / WebPの共通操作。HEICがブラウザから渡る場合は同じ変換経路
- 20MiB・3200万画素・8192px・8:1と編集元上限の境界、破損、通信中断、45秒超過からの復帰
- crop data改ざん、別画像のID、古いタブ、部分失敗、未添付Blob清掃
- カード、ヒーロー、OGP、未設定時の共通ロゴ

HEIC decoderの配布条件確認、ステージング画像移行、本番dry-runの承認が終わるまで本番切替を行わない。

## 9. FilePond・検証機能の撤去条件

次をすべて満たした後に撤去する。

1. User / Store / Boothの通常経路が新方式へ切り替わり、ステージング確認済み
2. 本番既存画像移行と事後照合が完了
3. 監視期間中に旧経路へ戻す必要がない
4. 未移行・失敗対象が0件、または個別対応Issueへ明示的に分離済み

FilePond本体、plugin、head partial、Stimulus controller、SCSS、JavaScriptテスト、development用検証Controller/View/Model/tableを削除する。共通画像検証ページは実装・移行確認まで維持し、その後route、dashboardリンク、Controller/View、検証用Service/Model/table/job、環境変数を削除する。direct uploadを本番採用しないため、検証専用に追加したステージングS3のPUT CORSも保存済みの変更前JSONへ戻し、差分なしを確認する。

## 10. 実装順

1. 保存基盤
2. 共通画像編集UIとHEIC変換
3. User、Store、Boothの通常経路
4. 共通UIのステージング実機確認
5. 既存画像移行の実装と段階実行
6. FilePond・検証専用機能の撤去、最終回帰確認

各段階の子Epic・子Issueと依存関係は #1134 および #1127 を正とする。
