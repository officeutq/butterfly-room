# Terraform apply前チェックリスト

## 認証とツール

- [ ] `aws sts get-caller-identity --profile butterfly-room-staging --no-cli-pager`のAccountが`137775584467`
- [ ] Arnに`assumed-role/butterfly-room-staging-deployer`を含む
- [ ] `default`と`butterfly-room-readonly`を使用していない
- [ ] Terraformのバージョンを記録した
- [ ] `terraform init -backend=false`が成功した
- [ ] `terraform validate`が成功した

## 既存リソース

- [ ] VPCが`vpc-05d7e03b48c391388`
- [ ] public subnetが`subnet-0c1b927d05f43c408`
- [ ] ALBが`butterfly-room-alb`
- [ ] HTTP/HTTPS listenerのdefault actionが本番Target Groupのまま
- [ ] Hosted Zoneが`butterflyve.jp`
- [ ] RDS identifierが`corporate-prod`
- [ ] `staging.butterflyve.jp`レコードがまだ存在しない、またはTerraform stateと一致
- [ ] HTTP/HTTPS listener priority `10`が空いている。自動チェック結果も`available=true`

## plan安全性

- [ ] destroy 0件
- [ ] replace 0件
- [ ] 既存EC2、RDS、S3、Target Groupにchangeがない
- [ ] 既存ALB本体にchangeがない
- [ ] listener default actionにchangeがない
- [ ] `staging.butterflyve.jp`以外のDNSにchangeがない
- [ ] 既存VPC、subnet、Hosted Zone、RDSはdata sourceのreadだけ
- [ ] 作成名が`butterfly-room-staging-*`または`butterfly-room-staging`
- [ ] 作成対象に`app=butterfly-room`、`env=staging`、`managed_by=terraform`タグが付く

## セキュリティと事故防止

- [ ] SSH CIDRは空、または承認済み`/32`のみ
- [ ] EC2 SGの3000/tcpは既存ALB SGからのみ
- [ ] S3は`butterfly-room-staging`だけで、公開ブロック、SSE-S3、versioningが有効
- [ ] IAM独自ポリシーに`Resource: "*"`がない
- [ ] `AmazonSSMManagedInstanceCore`のワイルドカード権限を、Session Manager運用に必要なAWS管理ポリシーとして承認した
- [ ] SNS権限と`ivs:DeleteStage`がない
- [ ] IVS権限がStage ARNと`app/env`タグ条件に制限されている
- [ ] User Dataに秘密値、GitHub token、private clone、`.env.staging`生成がない
- [ ] Terraform state/plan/variablesに秘密値がない

## 既知の権限不足

2026-08-02の読み取り確認では、staging deployerに以下が拒否されました。

- `rds:DescribeDBInstances`
- `iam:GetRolePolicy`（staging deployer自身のinline policy参照）

`terraform plan`で同じ拒否が出た場合、AdministratorAccessは要求しません。対象リソースを限定した`rds:DescribeDBInstances`など、失敗したActionだけを管理者へ申請します。`iam:GetRolePolicy`はTerraform対象外のdeployer policy調査にのみ必要であり、planに不要なら追加しません。

## 人間の承認

- [ ] DB管理者がSQLをレビューした
- [ ] ステージングDBパスワードの登録先を決めた
- [ ] メールredirect先を承認した
- [ ] Stripe test accountとWebhook endpointを承認した
- [ ] Basic認証値を安全な保管先へ登録した
- [ ] 月次timerは初期無効のままと確認した
- [ ] apply実行者と実行時刻を記録した
