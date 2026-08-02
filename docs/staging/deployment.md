# ステージング環境デプロイ手順

## 構成方針

`staging.butterflyve.jp`は既存のButterfly Room VPC、public subnet、ALB、HTTPS/HTTP listener、Route 53 Hosted Zone、RDSインスタンスを共有します。ステージング専用にEC2、Security Group、IAM role/instance profile、S3 bucket、Target Group、listener host rule、ACM証明書、DNSレコードを作成します。

CloudFrontとWAFは今回追加しません。RDSインスタンスは共有しますが、DBは`butterfly_room_staging`、ユーザーは`butterfly_room_staging_user`へ分離します。本番データはコピーしません。

## 1. Terraform前提確認

1. [pre_apply_checklist.md](pre_apply_checklist.md)を完了する。
2. AWS CLIの`butterfly-room-staging`プロファイルが`assumed-role/butterfly-room-staging-deployer`を利用していることを確認する。
3. `infra/terraform/environments/staging/terraform.tfvars.example`を`terraform.tfvars`へ複製し、listener priorityとSSH CIDRを確認する。
4. Terraformが未導入なら、組織で承認された配布元から導入する。今回の端末では未導入のため、Codexはインストールしていない。
5. `terraform fmt -recursive`、`terraform init -backend=false`、`terraform validate`、`terraform plan`を実行する。
6. planに本番リソースのchange/destroy/replaceが1件でもあれば中止する。

`terraform apply`は承認後に人間が実行します。この準備作業では実行していません。

## 2. DBを手動準備

[ops/staging/README.md](../../ops/staging/README.md)をDB管理者がレビューし、`ops/staging/create_staging_database.sql`を手動実行します。パスワードは対話入力し、Gitへ保存しません。

## 3. EC2へ接続

Terraform apply後、EC2を人間が起動します。推奨はAWS Systems Manager Session Managerです。Terraformは`AmazonSSMManagedInstanceCore`をアタッチし、User Dataは既存のSSM Agentを有効化します。

```powershell
aws ssm start-session `
  --target "<staging instance id>" `
  --profile butterfly-room-staging `
  --region ap-northeast-1 `
  --no-cli-pager
```

SSHを使う場合だけ、`ssh_allowed_cidrs`へ管理者の固定グローバルIP `/32`を設定し、鍵を安全に管理します。`0.0.0.0/0`は設定しません。

## 4. リポジトリと秘密値を配置

User Dataはprivate repositoryをcloneせず、秘密値も生成しません。人間が`/opt/butterfly-room/current`へリポジトリを配置します。

```bash
cd /opt/butterfly-room/current
cp .env.staging.example .env.staging
chmod 600 .env.staging
```

`.env.staging`へ秘密情報保管システムから値を入力します。必要な主な変数は以下です。

- `DATABASE_URL`: DB名を`butterfly_room_staging`、`sslmode=require`とする
- `RAILS_MASTER_KEY`、`SECRET_KEY_BASE`
- `AWS_S3_BUCKET=butterfly-room-staging`
- `SES_SMTP_USERNAME`、`SES_SMTP_PASSWORD`
- `MAIL_DELIVERY_MODE=redirect`、`MAIL_REDIRECT_RECIPIENT`
- `SMS_DELIVERY_MODE=mock`
- Stripe test keyとステージング用Webhook secret
- `IVS_STAGE_ENV=staging`、`IVS_STAGE_NAME_PREFIX=br-staging`
- `GTM_ENABLED=false`
- Basic認証ユーザー名とパスワード
- 必要なBanuba、DeepAR、Google Mapsのステージング用値

実値をGit、Terraform、User Data、systemd unitへ記載しません。初期運用は手動`.env.staging`を採用します。将来Parameter Storeを使う場合もSecureString、専用KMS key、パス限定IAM、監査ログを設計してから移行します。

## 5. appを先に起動して確認

```bash
cd /opt/butterfly-room/current
export STAGING_ENV_FILE=./.env.staging
docker compose -f docker-compose.staging.yml config --quiet
docker compose -f docker-compose.staging.yml build app
docker compose -f docker-compose.staging.yml run --rm app bundle exec rails db:prepare
docker compose -f docker-compose.staging.yml run --rm app bundle exec rails db:seed
docker compose -f docker-compose.staging.yml up -d app
curl --fail --silent --show-error http://127.0.0.1:3000/up
docker compose -f docker-compose.staging.yml logs --tail=100 app
```

起動時安全ガードが失敗した場合、変数の値をログへ貼らず、変数名と設定元を確認します。`db:prepare`が本番DBを指していないことを事前確認します。

## 6. workerを起動

appの`/up`成功後にだけworkerを起動します。

```bash
docker compose -f docker-compose.staging.yml up -d worker
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs --tail=100 worker
```

## 7. systemdを有効化

User Dataはunitファイルを配置しますが、自動enableしません。手動起動が安定してから有効化します。

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

timerは初期状態で無効です。まずserviceを手動実行し、必ずステージングDBの結果だけが変わることを確認します。

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

`Persistent=false`のため、EC2停止中に過ぎた実行を次回起動時に自動追実行しません。停止期間分の月次処理は、人間が対象月と既存レコードを確認して手動判断します。

## 9. 外形確認

[post_apply_checklist.md](post_apply_checklist.md)に従い、ALB health、HTTPS、Basic認証、メールredirect、SMS mock、Stripe test、GTM非出力、noindex、S3分離、IVS Stageタグを確認します。

## 10. EC2停止

ステージングを使わない時間帯は、人間がapp serviceを停止してからEC2を停止します。Elastic IPを付与しないため、再起動後のpublic IPは変わりますが、ALBのinstance target登録には影響しません。EC2停止中は月次timerが実行されず、RDSとS3は継続課金されます。
