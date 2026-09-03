# 2画像の送信・一時保存検証（#1132）

## 範囲と現在の判断

編集元JPEGと表示用JPEGを、同じsystem_admin（システム管理者）の一時検証としてActive Storageへ保存する。`ImageUploadVerificationRun` に送信者、方式、2個のBlob参照、クロップ情報、状態、期限、測定結果を保存する。本番のUser / Store / Boothの画像添付・カラム・既存画像は変更しない。検証テーブルは一時データのため清掃時に物理削除する。業務履歴を物理削除する処理ではない。

**方式はまだ未決定。** 最初の比較候補は既存方式に近いmultipartとする。直接送信の有利不利はS3・実機・低速回線での測定後に決める。ローカルDiskの結果をS3性能や本番採用判断へ読み替えない。#1133は通常画像の複数Blob更新・複製・競合・移行の試作、#1134で本番設計と実装Issueを確定する。

## 操作とデータ経路

1. ダッシュボード → 画像アップロード検証。従来の画像選択・HEIC変換・クロップ操作だけでは送信しない。
2. 「5. 2画像の一時保存・送信比較」で方式を選び、「2画像を一時保存して検証」を押す。
3. **開始時点のクロップで表示用JPEGを再生成**する。生成中にクロップが動いた場合は再試行を促し、画像と異なるJSONを送らない。テキスト欄を手編集しただけのJSONは送らず、実際のCropper状態を使う。
4. 共通の認証・認可・有効化設定で保護した `SystemAdmin::ImageUploadVerificationRunsController` → `ImageUploadVerifications::UploadService` を呼ぶ。
5. multipartは1回のファイル送信で2枚をRailsへ渡す。実体を検査してから保存し、保存先からストリームで読み戻してSHA-256の一致を確認する。直接送信はRails標準 `DirectUpload` で編集元→表示用の順にPUTし、所有する2個のsigned ID（署名付き識別子）を専用の完了APIへ渡す。
6. 直接送信後も、保存先を容量制限付きで読み戻し、実体検査を通過して初めて `complete` とする。Cookie認証・CSRF（意図しない外部サイトからの送信防止）を維持し、未ログイン・他ロール・無効時の全書込APIを拒否する。
7. 結果のJSONをコピーしてIssue #1132へ記録する。失敗時もエラーJSONを表示する。再試行は新しい検証ID・新しい2画像とし、不完全な組を使い回さない。画像差し替え・正規化設定変更・Turbo遷移・中止は送信を中断し、古い応答を新しい画面へ表示しない。

結果の `server_milliseconds` はmultipartでは検査・保存・読み戻し、直接送信では完了API内の読み戻し・検査を計測する。`client_milliseconds` は検証開始APIから完了まで（直接送信時のMD5計算を含む）。元画像の変換・クロップ生成は含まない。両方式のサーバー時間は処理範囲が異なり、単純な速度比較には使わない。転送100%と実体確認完了は区別する。ピークメモリは測定していない。

## 暫定上限と実体検査

| 項目 | 検証用の値 |
| --- | --- |
| 入力画像 | 既存の20MiB、通常3200万画素・HEIC標準1600万/比較3200万画素 |
| 送信する編集元JPEG | 20MiBまで。既定は800万画素/4096px、比較時も3200万画素/8192px以内 |
| 表示用JPEG | 5MiBまで、1024×1024または1200×630、品質0.90 |
| 縦横比 | 編集元の長辺/短辺は8以内。用途の最低幅・高さも必要 |
| クロップJSON | schemaVersion 1、4KiB以内、有限座標、範囲・比率・倍率・出力設定を検査 |
| ブラウザ通信 | 1リクエスト120秒、直接PUT URLは5分、検証操作は開始から15分 |
| 一時保持 | 利用者ごと20件まで、開始から1時間後に清掃対象 |
| ImageMagick | ヘッダー確認5秒、全画素デコード20秒、memory128MiB/map256MiB/disk512MiB/thread1 |

これらは本番採用値ではない。HEIC入力の容量と生成JPEGの容量は別々に検査する。実体はJPEG固定デコーダで読み、デコード前に寸法・画像数を照合し、その後全画素を読む。拡張子や申告MIMEだけを根拠にしない。ブラウザ生成JPEGを再圧縮せず、2枚とも同じバイト列を保持する。保存先の容量を信頼せず、読み戻し中に申告容量・用途上限を超えたら停止する。MD5と実byte数、検査済みmultipart画像とのSHA-256も照合する。

JSONと画像の**寸法・形式・範囲**の整合を検査するが、表示用画像の画素が編集元の指定範囲から生成されたことまではサーバーで再描画して証明していない。クロップ情報に編集元Blob IDを結びつける本番契約・改ざん方針は#1133/#1134で決定する。

## 所有権・失敗・清掃

- 検証行を `where(user: current_user)` で取得する。別ユーザー、別検証、役割を入れ替えたsigned ID、改ざんIDは完了に使えない。Blobのファイル名・キー・metadataはサーバーが決定する。元ファイル名は送信しない。リクエストの `verification` / `blob` 本文はログで伏せる。
- Blobレコードと検証行の参照を短いDB transaction（データベースの一連処理）で先に確定し、それから外部保存を行う。2枚目の失敗・完了のDB失敗でも、新規Blobを清掃する参照を残す。通常画像の参照は触らない。状態変更は行ロック下で照合し、中止後に成功へ戻せない。
- 中止APIはまず `canceled` にする。ブラウザの中止通知は回線断やページ終了時に届かないことがあるため、通知だけに依存しない。完了・失敗・未送信・中止の全状態を期限で清掃する。
- 清掃は `ImageUploadVerificationCleanupJob` を本番設定で5分ごとに実行。フラグを無効化しても清掃する。1回100行以内、当該検証IDの `image-upload-verification/` キーだけを対象にし、他用途へ添付されたBlobは拒否する。保存先削除に失敗した行は残し、次回再試行する。全未添付Blobの一括削除はしない。
- 署名済みPUTはブラウザの中止だけでは失効せず、期限内なら再送できる。このため即時purgeせず、発行上限15分＋URL5分に対して開始1時間後まで猶予を取る。期限前に開始した長時間PUTが清掃後に完了するケースは、この猶予だけで完全には防げない。[AWSの署名URLの仕様](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)を前提とする。
- ステージングのS3はバージョン管理有効。通常のキー削除では旧世代が残る。今回、バケットの自動削除設定は追加しない。検証終了後、署名URLの失効と進行中の送信がないことを確認し、検証prefixの現行・旧世代・削除マーカーを一覧で確認する。必要な後片付けは、検証用と確認できたキー・version IDだけを明示して行い、通常の添付には触れない。旧世代の物理削除は取り消せないため、設定の復元とは区別する。[S3のバージョン削除](https://docs.aws.amazon.com/AmazonS3/latest/userguide/DeletingObjectVersions.html)参照。
- 直接送信の一時Blobは署名URL期限まで書き換え可能なので、本番添付へそのまま昇格するコードは追加しない。#1133で、実体検査済みデータを別キーへ複製してから添付する等の不変化を検討する。

## 実行環境の調査（2026-09-03、変更せず読み取り）

- ステージング実行コードは#1137の `5a69c31`、Rails production / APP_ENV staging、検証フラグ有効、Pumaスレッド数2。
- 共有ALBの `idle_timeout.timeout_seconds=60`、`client_keep_alive.seconds=3600` をAWS APIで確認。60秒は無通信時間で、アップロード全体の所要時間上限ではない。共有ALB設定は変更しない。
- 配置済み `config/puma.rb` にbody容量制限・タイムアウトの明示設定なし。同梱Puma既定は `http_content_length_limit=nil`、`first_data_timeout=30`、`persistent_timeout=65`。後二者は業務リクエスト全体の制限ではない。
- 変更前のS3 CORSは `https://staging.butterflyve.jp` のGET/HEADのみ。バージョン管理Enabled、ライフサイクル設定は無しをAWS APIで確認した。今回のS3設定変更は、ブラウザからの直接送信比較に必要なPUT追加だけ。バージョン管理・公開設定・暗号化・ライフサイクル・IAM・本番S3・共有ALBは変更しない。既存ステージングEC2のIAM定義にはPutObject/GetObject/DeleteObjectがある。
- Rails側のJPEG容量検査は、WebサーバーやRackによるmultipart受信前の全体容量制限ではない。**25MiB＋multipart境界分の受信上限をどこで実施するかは未決定**。未知長body、低速接続、S3ダウンロード/アップロードのタイムアウトと再試行値、ピークメモリは実測と設定判断が必要。本番へ公開する前に#1134で解消する。

## 検証・起動手順

ローカルの既存Docker環境:

```bash
docker compose exec -T app bin/rails db:migrate
docker compose exec -T app bin/rails test test/services/image_upload_verifications test/integration/system_admin_image_upload_verification_runs_test.rb test/integration/system_admin_image_upload_verification_test.rb test/services/image_attachments/update_service_test.rb
npm run test:js
node --test test/javascript/browser/image_upload_transfer_test.cjs
```

ローカルでは定期ジョブを起動していないため、期限を過ぎた検証データを次で清掃する。期限前のデータは削除しない。

```bash
docker compose exec -T app bin/rails runner 'ImageUploadVerifications::CleanupService.new.call'
```

実際のRails画面・認証・Disk保存まで確認するブラウザテストは明示実行に限る。ローカル専用system_adminの認証情報を環境変数 `IMAGE_UPLOAD_VERIFICATION_EMAIL` / `IMAGE_UPLOAD_VERIFICATION_PASSWORD` に設定し、Gitやログに残さない。

```powershell
$env:IMAGE_UPLOAD_VERIFICATION_BASE_URL = "http://app.localhost:3000"
# 必要なら $env:IMAGE_VERIFICATION_BROWSER = "firefox" または "webkit"
node --test test/javascript/browser/image_upload_transport_rails_test.cjs
```

このテストは生成した4色画像だけを使い、両用途×両方式で4件の検証を作って中止状態にする。期限後清掃の対象となる。本番・ステージングURLはテスト側で拒否する。

ローカルChromiumの初回測定例（4色の小容量画像、開発モード、byte / ms）:

| 用途 | 2画像の合計容量 | multipartの全体時間 | 直接送信の全体時間 |
| --- | ---: | ---: | ---: |
| square | 31922 | 3443.8 | 7316.9 |
| social | 18123 | 2538.2 | 6906.2 |

直接送信はローカルDiskなので実際にはRailsへPUTしており、リクエスト回数・開発時処理・初回読込が結果へ影響する。実写真/S3/モバイル回線の性能比較ではない。4色図の出力容量もブラウザのJPEGエンコーダにより異なる。

自動確認対象: 認可・無効化・CSRF、実Disk PUTとmultipart、2画像の実体・寸法・バイト一致、別ユーザー/別検証/役割入替/改ざんsigned ID、容量・破損・不足ファイル、部分保存失敗、DB完了失敗、中止中の完了、再試行、期限・20件上限、清掃失敗再試行、関係ないBlobの維持。ブラウザでは開始時クロップとの整合と、画像差し替え時の中止・古い結果の抑制も確認する。

2026-09-03、関連Rails 33件/254 assertions、JavaScript 78件、実Cropperブラウザでのクロップ・中止検証が通過した。ローカルの実Rails/Stimulus/Active Storageを使った両用途×両方式の4送信はChromium・Firefox・WebKitの3エンジンで通過した（390px幅の横はみ出し無し）。**PC上のWebKitであり、iPhone実機の保存確認ではない。** RuboCop 546ファイル、Zeitwerk、Brakeman 7.1.2でエラー・警告なし。`bin/brakeman` の最新バージョン必須チェックは既存7.1.2が古いため停止したので、CIと同じ `bundle exec brakeman --no-pager` で実スキャンを行った。CSSビルド成功、既存Sass非推奨警告あり。Terraform fmt/validate成功。

## ステージング適用前提と残作業

2026-09-03、ユーザー承認に基づき、ステージングの検証テーブル追加・CORSのPUT追加・app/worker反映を実施した。候補は `d9ae003`。反映前の設定・イメージと切戻し手順は [ステージング反映記録](../staging/image_upload_verification_1138.md) を参照する。自動削除設定は追加していない。

ステージングの候補コンテナ内で、既存管理者の認証を検証プロセス内だけに設定し、Railsのリクエスト経路から生成したグラデーションJPEGを送った。両用途×両方式の計4件で実S3保存・読み戻しSHA-256一致・中止を確認した。直接送信では実際の署名付きURLへHTTPの事前確認（preflight）とPUTを実行し、許可元ヘッダーも一致した。実インターネット経由のブラウザ送信・iPhone・速度比較の代替ではない。

| 用途 | 2枚の合計byte | multipartのサーバー時間 | 直接送信の完了API時間 |
| --- | ---: | ---: | ---: |
| social | 49668 | 541.1ms | 225.3ms |
| square | 45726 | 389.9ms | 224.5ms |

両方式の時間の計測範囲は異なるため、直接送信が速いという採用判断には使わない。ダッシュボードのリンク、新しい保存欄、未ログイン拒否・非管理者403、HTTPS `/up`、新JS配信、ALB正常性を確認した。既存の画像添付5件はID・所有先・Blob参照も不変だった。清掃の5分間隔登録と実workerでの生成テストデータ清掃も確認した。

以下は適用条件・継続検証の手順。1〜3は今回実施済みで、未確認の実機・境界・低速回線は継続する。

1. `docs/staging/pre_apply_checklist.md` に従い、変更前のCORSを保存する。保存planでstaging bucketのCORSにPUTを追加する1件だけであることを確認後にapplyする。別の変更があればそのplanは適用しない。自動削除設定は追加しない。
2. staging DB/APP_ENV/保存先を確認して、検証テーブルのmigrationを実行する。本番DBへは実行しない。
3. appに加えてworkerも同じコードへ更新し、定期清掃ジョブの登録・稼働を確認する。従来の検証のようなappだけの更新では清掃できない。更新前のapp・workerは別々のイメージを保護し、環境設定をバックアップする。DB追加は検証テーブル1個に限定する。アプリ切戻し時は追加テーブルを残せるため、検証データを意図せず消す自動DB巻戻しは行わない。
4. 既存のフラグ付き管理者ページで実S3 PUT・multipart・実体検査・再試行・中止・清掃を確認する。ログインなしや他ロールは拒否されることも再確認する。
5. iPhone 15 Proの既に変換成功した12MP/24MP HEICと、低速回線・大きいJPEGで2方式のJSONを採取する。入力ファイル名はIssueへ載せない。変換結果の画質判断と送信結果を混同しない。
6. S3のCORS・HTTP失敗、容量境界、ALB無通信タイムアウト、サーバー/ブラウザのメモリ、途中離脱後の現行/旧世代削除を記録する。期限切れPUTの再送や清掃後の遅延PUTも扱う。
7. #1132へ採用方式・本番容量候補と残課題を記録して完了判断する。#1131からの実機詳細操作・他端末・ライセンス等の未確認事項も#1134の設計確定時に引き継ぐ。

`ImageAttachments::UpdateService` の現行の「正規化→新Blobアップロード→DB更新→旧Blob清掃」は参照したが、そのまま呼ぶと二重JPEG化・単一添付更新になるため、この検証からは呼ばない。Serviceに状態変更とtransactionを置き、事前アップロード・失敗時の新Blob清掃という責務を維持する。既存処理の具体的な再利用・分割は#1133の試作結果で確定する。
