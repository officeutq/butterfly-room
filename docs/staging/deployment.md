# ステージング環境デプロイ手順

## 構成方針

`staging.butterflyve.jp`は既存のButterfly Room VPC、public subnet、ALB、HTTP/HTTPS listener、Route 53 Hosted Zone、RDS instanceを共有します。ステージング専用にEC2、security group、IAM role/instance profile、S3 bucket、Target Group、listener host rule、ACM certificate、DNS recordを作成しています。

CloudFrontとWAFは追加しません。RDS instanceは共有しますが、DBは`butterfly_room_staging`、roleは`butterfly_room_staging_user`へ分離します。本番データはコピーしません。

## 現在の完了状況（2026-08-02）

- Terraform managed resource 23件はAWSへ適用済みで、apply後planは`No changes`
- ACM certificate、Route 53 Alias、staging EC2、Target Group登録は作成済み
- staging EC2はコスト抑制のため停止中
- staging role、staging DB、staging DB ACLは作成・検証済み
- staging userからproduction DBへの`CONNECT` / `TEMPORARY`分離と実接続拒否を確認済み
- production Railsの既存接続維持を確認済み
- アプリ、`.env.staging`、Docker containerは未配置・未起動

## 1. Terraform変更時の確認

1. [pre_apply_checklist.md](pre_apply_checklist.md)を完了する。
2. AWS CLIの`butterfly-room-staging` profileが`assumed-role/butterfly-room-staging-deployer`を利用していることを確認する。
3. `infra/terraform/environments/staging`でremote S3 backendを初期化する。
4. `terraform fmt -recursive`、`terraform validate`、保存済みplanを確認する。
5. planに本番resourceのchange/destroy/replaceが1件でもあれば中止する。
6. 承認済みの保存planだけをapplyし、apply後planの`No changes`を確認する。

既存ALBのdefault action、本番Target Group、RDS instance、本番S3、既存DNSはTerraformで変更しません。

### Google Sheets認証Secretの参照

Google Sheets用のstagingサービスアカウント認証情報は、既存のAWS Secrets Manager Secretで管理します。Secret自体とSecret値はTerraformで作成・更新せず、`DescribeSecret`だけを呼ぶexternal data sourceで名前とARNを参照して、staging EC2 roleの読取対象ARNを限定します。

環境分離、実値の確認場所、鍵rotation、Spreadsheet共有、CloudTrail、障害対応は[LP行動分析 Google Sheets連携運用手順](../ops/lp_analytics_google_sheets.md)に従います。

Secret名は公開リポジトリへ固定せず、Git管理外の`infra/terraform/environments/staging/terraform.tfvars`で次のvariableへ設定します。

```hcl
google_sheets_credentials_secret_name = "<existing-staging-secret-name>"
```

- 設定するのはSecret名だけで、ARNやサービスアカウントJSONは記載しない
- Secret値、Secret version、private keyはTerraformから参照しない
- `terraform.tfvars`をGitへ追加しない
- planでは`data.external.google_sheets_credentials_secret`が既存Secretの名前とARNのreadだけであることを確認する
- IAM policyのResourceがdata sourceから得たstaging用Secret ARNの1件だけであることを確認する
- production用SecretのARNや権限がplanへ含まれていた場合は中止する

## 2. DB手動作業

詳細は[ops/staging/README.md](../../ops/staging/README.md)に従います。SQLはTerraform、User Data、systemd、Rails taskから実行しません。

### 共通前提

- PostgreSQL 18系clientを使う。実施時はclient 18.4、server 18.3だった
- staging EC2からRDSのTCP/5432到達を先に確認する
- RDS master userは`postgres`
- TLS接続を確認する
- passwordは`\password`で非表示入力し、SQLやGitへ保存しない

### staging DB作成

`ops/staging/create_staging_database.sql`を`postgres` DBへ接続して実行します。Amazon RDSでは、別roleをDB ownerに指定すると`must be able to SET ROLE`になる場合があります。このSQLは事前membershipを記録し、必要な場合だけ`SET TRUE`で一時的にSET ROLE可能にします。SQL自身が変更したmembershipだけを処理後に元へ戻します。

`CREATE DATABASE`はtransaction外で実行されるため、途中失敗時は再実行前に一時membershipを確認します。復旧条件とコマンドはops READMEを参照し、事前状態が不明な場合は推測で`REVOKE`しません。

`\password`は成功メッセージを出さずpromptへ戻る場合があります。必ずstaging userでstaging DBへ実ログインし、passwordとTLSを確認します。

### production DB接続分離

`ops/staging/restrict_production_database_access.sql`は**本番DBの権限変更**を行うため、DB作成とは別の承認・手順で実行します。

実行前にproduction DBの`datacl`、login可能role、現在のproduction接続user、`application_name`、client、接続数を確認します。`PUBLIC`から`CONNECT` / `TEMPORARY`を削除する前に、実際のproduction app roleへ同権限を明示付与し、`rdsproxyadmin`へ`CONNECT`を残します。

既存sessionが維持されても、新規connectionは影響を受けます。変更直後にproduction app roleの新規接続、本番Rails接続、health check、staging userの接続拒否を確認します。

### 分離検証

`ops/staging/verify_staging_database_isolation.sql`は参照専用です。DB/schema/object権限、production app role、`rdsproxyadmin`、一時membershipを確認します。最後にstaging userからproduction DBへの実接続が拒否されることを別processで確認します。

## 3. EC2への接続

EC2起動は人間が承認して実行します。推奨接続はAWS Systems Manager Session Managerです。

```powershell
aws ssm start-session `
  --target "<staging instance id>" `
  --profile butterfly-room-staging `
  --region ap-northeast-1 `
  --no-cli-pager
```

SSHを使う場合だけ、`ssh_allowed_cidrs`へ承認済み固定global IP `/32`を設定します。`0.0.0.0/0`は設定しません。

## 4. Repositoryと秘密値の配置

User Dataはprivate repositoryをcloneせず、秘密値も生成しません。人間が`/opt/butterfly-room/current`へrepositoryを配置します。

```bash
cd /opt/butterfly-room/current
cp .env.staging.example .env.staging
chmod 600 .env.staging
```

`.env.staging`へ秘密情報管理systemから値を入力します。主な設定は次のとおりです。

- `DATABASE_URL`: DB名を`butterfly_room_staging`、`sslmode=require`以上にする
- `RAILS_MASTER_KEY`、`SECRET_KEY_BASE`
- `AWS_S3_BUCKET=butterfly-room-staging`
- `SES_SMTP_USERNAME`、`SES_SMTP_PASSWORD`
- `MAIL_DELIVERY_MODE=redirect`、`MAIL_REDIRECT_RECIPIENT`
- `SMS_DELIVERY_MODE=mock`
- Stripe test keyとstaging用Webhook secret
- `IVS_STAGE_ENV=staging`、`IVS_STAGE_NAME_PREFIX=br-staging`
- `GTM_ENABLED=false`
- Basic認証ユーザー名とpassword
- 必要なBanuba、DeepAR、Google Mapsのstaging用値

実値はGit、Terraform、User Data、systemd unitへ記載しません。

## 5. appを先に起動して確認

```bash
cd /opt/butterfly-room/current
export STAGING_ENV_FILE=./.env.staging
docker compose -f docker-compose.staging.yml config --quiet
docker compose -f docker-compose.staging.yml build app
docker compose -f docker-compose.staging.yml run --rm app bundle exec rails db:prepare
docker compose -f docker-compose.staging.yml run --rm app bundle exec rails db:seed
docker compose -f docker-compose.staging.yml up -d app
curl --fail --silent --show-error \
  --output /dev/null \
  --write-out '%{http_code}\n' \
  -H 'Host: staging.butterflyve.jp' \
  http://127.0.0.1:3000/up
docker compose -f docker-compose.staging.yml logs --tail=100 app
```

RailsのHost AuthorizationによりHost headerなしのloopback確認は403になり得るため、上記のstaging hostを付けます。起動時安全guardが失敗した場合、値をlogへ貼らず変数名と設定元を確認します。`db:prepare`前にDB名が`butterfly_room_staging`であることを再確認します。

build前に`df -h /`と`docker system df`を確認します。空き容量不足時は、稼働中imageと明示的に付けたrollback tagを残したまま、未使用build cacheだけを`docker builder prune`で削除します。対象を確認せず`docker system prune -a`やvolume削除を実行しません。

## 6. workerを起動

appの`/up`成功後にだけworkerを起動します。

```bash
docker compose -f docker-compose.staging.yml up -d worker
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs --tail=100 worker
```

## 7. systemdを有効化

User Dataはunit fileを配置しますが自動enableしません。手動起動が安定してから有効化します。

```bash
sudo systemctl daemon-reload
sudo systemctl enable butterflyve-staging-app.service
sudo systemctl start butterflyve-staging-app.service
sudo systemctl status butterflyve-staging-app.service
```

停止:

```bash
sudo systemctl stop butterflyve-staging-app.service
sudo systemctl disable butterflyve-staging-app.service
```

## 8. 月次精算timer

timerは初期状態でdisabledです。まずserviceを手動実行し、staging DBの結果だけが変わることを確認します。

```bash
sudo systemctl start butterflyve-monthly-settlement-staging.service
sudo journalctl -u butterflyve-monthly-settlement-staging.service --since today
```

承認後の有効化と無効化:

```bash
sudo systemctl enable --now butterflyve-monthly-settlement-staging.timer
sudo systemctl list-timers butterflyve-monthly-settlement-staging.timer
sudo systemctl disable --now butterflyve-monthly-settlement-staging.timer
```

`Persistent=false`のため、EC2停止中に過ぎた実行を次回起動時に自動追実行しません。

## 9. 外形確認

[post_apply_checklist.md](post_apply_checklist.md)に従い、ALB health、HTTPS、Basic認証、mail redirect、SMS mock、Stripe test、GTM無効、noindex、staging S3、IVS Stage tagを確認します。

## 10. EC2停止

使わない時間帯はapp serviceを停止してからEC2を停止します。Elastic IPがないため再起動後のpublic IPは変わりますが、ALBのinstance target登録には影響しません。EC2停止中は月次timerが動かず、RDSとS3は継続課金されます。
