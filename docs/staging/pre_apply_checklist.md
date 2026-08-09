# Terraform apply前チェックリスト

このチェックリストは今後Terraformを変更・再適用するときに使用します。DB作成・DB権限変更はTerraform applyに含めません。

## 認証とtool

- [ ] `aws sts get-caller-identity --profile butterfly-room-staging --no-cli-pager`のaccountが対象accountと一致
- [ ] caller ARNに`assumed-role/butterfly-room-staging-deployer`を含む
- [ ] `default`と`butterfly-room-readonly`を使用していない
- [ ] Terraform versionを記録した
- [ ] remote S3 backendで`terraform init -reconfigure`が成功した
- [ ] `terraform validate`が成功した

## 既存resource

- [ ] VPCとpublic subnetが想定どおり
- [ ] ALBが`butterfly-room-alb`
- [ ] HTTP/HTTPS listenerのdefault actionが本番Target Groupのまま
- [ ] Hosted Zoneが`butterflyve.jp`
- [ ] RDS identifierが`corporate-prod`
- [ ] `staging.butterflyve.jp` recordがTerraform stateと一致
- [ ] listener priority `10`がstaging ruleに割り当て済みで競合しない

## planの安全性

- [ ] destroy 0件
- [ ] replace 0件
- [ ] 本番EC2、RDS、S3、Target Groupにchangeがない
- [ ] 既存ALB本体にchangeがない
- [ ] listener default actionにchangeがない
- [ ] `staging.butterflyve.jp`以外のDNSにchangeがない
- [ ] 既存VPC、subnet、Hosted Zone、RDSはdata sourceのreadだけ
- [ ] 作成名が`butterfly-room-staging-*`または`butterfly-room-staging`
- [ ] 作成対象に`app=butterfly-room`、`env=staging`、`managed_by=terraform`tagが付く

## Securityと事故防止

- [ ] SSH CIDRは空、または承認済み`/32`のみ
- [ ] EC2 security groupの3000/tcpはALB security groupからのみ
- [ ] staging S3だけが対象で、public block、SSE-S3、versioningが有効
- [ ] IAM独自policyに不要な`Resource: "*"`がない
- [ ] `AmazonSSMManagedInstanceCore`はSession Manager運用に必要なAWS managed policyとして承認済み
- [ ] Google Sheets認証用data sourceは`DescribeSecret`で既存のstaging Secretの名前とARNだけを参照し、Secret値・version・resource policyを参照していない
- [ ] staging EC2 roleのSecrets Manager権限は対象のstaging用Secret ARN 1件だけに制限されている
- [ ] production用Google Sheets認証Secretへの権限がない
- [ ] SNS permissionと`ivs:DeleteStage`がない
- [ ] IVS permissionがStage ARNと`app/env`tag条件に制限されている
- [ ] User Dataに秘密値、GitHub token、private clone、`.env.staging`生成がない
- [ ] Terraform state、plan、variablesに秘密値がない

## DB作業との分離

- [ ] Terraform planにRDS instance、DB role、DB ACLの変更がない
- [ ] staging DB作成SQLはapplyから自動実行されない
- [ ] production DB分離SQLはapplyから自動実行されない
- [ ] production DBの`PUBLIC`権限変更は別途DB管理者が承認する
- [ ] production app roleと`rdsproxyadmin`へ残す権限を確認した
- [ ] 変更前後のproduction接続、新規接続、health check確認担当を決めた

## 人間の承認

- [ ] DB管理者がSQLと復旧手順をreviewした
- [ ] staging DB passwordの登録先を決めた
- [ ] mail redirect先を承認した
- [ ] Stripe test accountとWebhook endpointを承認した
- [ ] Basic認証値を安全な保管先へ登録した
- [ ] 月次timerは初期disabledのままと確認した
- [ ] apply実行者と実行時刻を記録した
