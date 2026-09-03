# 画像2枚の一時保存検証: ステージング反映と切戻し（#1132 / #1138）

## 変更する範囲

- staging DB `butterfly_room_staging` に `image_upload_verification_runs` だけを追加する。既存の画像添付・業務テーブルのデータ移行やseedは実行しない。
- `butterfly-room-staging` のCORS（ブラウザの別オリジンへの送信許可）は既存GET/HEADへPUTだけ追加する。許可元は `https://staging.butterflyve.jp` のまま。
- app / workerをPR #1138の同じ候補イメージへ更新する。既存の検証フラグは有効のまま、`.env.staging` は変更しない。
- バケットの公開設定、暗号化、バージョン管理、自動削除、IAM、共有ALB、本番環境は変更しない。

## 変更前の復元点（2026-09-03）

EC2: `i-00a52dfe98ba9a9a7`、配置先: `/opt/butterfly-room/current`。

- コード: `5a69c31450fb855ff96bbfe522ba78d10942db3a`。保護ブランチ: `codex/staging-before-upload-1138`。
- app: `butterfly_room_staging:rollback-app-before-upload-1138`（`dc6ad151375a`）。
- worker: `butterfly_room_staging:rollback-worker-before-upload-1138`（`8d2cb6177592`）。更新前はappとworkerのバージョンが異なるため、別々に保護する。
- 環境設定とCompose原本: `/opt/butterfly-room/shared/image-upload-verification-1138-20260903/env.before`、`compose.before.yml`。ディレクトリ700、環境ファイル600。秘密値をGitや報告へ貼らない。
- DB: 追加テーブルなし、最新適用migrationは `20260827010000`。
- CORS: 以下の内容をローカルのGit管理外 `tmp/image-upload-staging-1138/cors.before.json` に保存した。

```json
{"CORSRules":[{"AllowedHeaders":["*"],"AllowedMethods":["GET","HEAD"],"AllowedOrigins":["https://staging.butterflyve.jp"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":3600}]}
```

## 適用時の注意

通常のTerraform planでは、既存の「最新AMIを取得する」設定により、今回と無関係なEC2とTarget Group登録の再作成が提案された。このplanは適用しない。今回に限って `-target=aws_s3_bucket_cors_configuration.app` で保存planを作り、**追加0・更新1・削除0、PUT追加だけ**を確認して適用する。全体planの差分解消やAMI固定は別作業とする。

必須variable `google_sheets_credentials_secret_name` は既存Terraform stateのdata sourceから名前だけを再利用する。Secret値は取得・更新しない。`terraform init -reconfigure`、validate、保存planの確認を省略しない。

DB接続先を確認した候補コンテナから、migration `20260903130000` だけを実行する。未適用migrationが別にあれば中止する。appの `/up` が成功してからworkerを更新する。清掃ジョブが5分ごとに登録されたことを確認する。

## アプリの切戻し

再度反映後のHEADとコンテナを確認し、追跡ファイルに別作業の変更があれば中止する。設定を変えていないため、通常は環境ファイルの上書き復元は不要。

1. `codex/staging-before-upload-1138` へ切り替える。未追跡の既存画像調査ファイルは削除しない。
2. `rollback-app-before-upload-1138` を `latest` にタグ付けし、`docker compose -p current -f docker-compose.staging.yml up -d --no-deps --no-build --force-recreate app` を実行する。`STAGING_ENV_FILE` は元の `.env.staging` を明示する。
3. `/up` 確認後、`rollback-worker-before-upload-1138` を `latest` にタグ付けし、同じComposeコマンドでworkerだけを再作成する。
4. `latest` は旧appのタグへ戻す。稼働中コンテナのイメージIDをそれぞれ照合する。この状態でapp/workerをまとめて再作成すると旧workerと異なるイメージになるので注意する。

追加テーブルは旧アプリから参照されないため、まず残したままアプリを戻せる。完全にDB追加も取り消す場合は、検証の停止・一時Blobの清掃・必要な検証結果の退避後に、今回のmigrationだけをdownする。テーブル削除は検証結果の削除を伴うので自動では実行しない。単純な `db:rollback` で別のmigrationを巻き戻さない。

## CORSの切戻し

通常は `storage.tf` の許可メソッドをGET/HEADへ戻し、同じ対象限定の保存planで更新1件だけを確認して適用する。これでAWS設定とTerraformを一致させる。

緊急時は、変更後に他のCORS変更が入っていないことを確認して、保存済みJSONを `aws s3api put-bucket-cors --bucket butterfly-room-staging --expected-bucket-owner 137775584467 --cors-configuration file://tmp/image-upload-staging-1138/cors.before.json --profile butterfly-room-staging --region ap-northeast-1` で復元できる。その場合も後でTerraformコードをGET/HEADへ戻して差分を確認する。

S3のバージョン管理は変えない。アプリの清掃後も検証画像の旧世代が残り得る。旧世代の後片付けは検証prefix・キー・version IDを確認して別途実施する。設定の復元と、画像の物理削除（取り消せない）は区別する。
