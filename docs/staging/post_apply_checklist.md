# Terraform apply後チェックリスト

## AWSリソース

- [ ] 新規EC2が`t3.micro`、Amazon Linux 2023、暗号化gp3 20GiB
- [ ] EC2にElastic IPがなく、IMDSv2必須、CPU creditがstandard
- [ ] EC2 SGの3000/tcpはALB SGだけから許可
- [ ] S3 `butterfly-room-staging`の公開ブロック、owner enforced、SSE-S3、versioning、CORSを確認
- [ ] Target Groupのport 3000、`/up`、matcher 200、deregistration 300秒、stickiness offを確認
- [ ] Targetがhealthy
- [ ] HTTPのstaging host ruleだけがHTTPSへ301 redirect
- [ ] HTTPSのstaging host ruleだけがstaging Target Groupへforward
- [ ] 本番listener default actionが変更されていない
- [ ] ACM証明書がIssuedで、SNIへ追加されている
- [ ] `staging.butterflyve.jp` Aliasが既存ALBだけを指す

## アプリ

- [ ] `.env.staging`がmode 600でGit管理外
- [ ] `DATABASE_URL`のDB名が`butterfly_room_staging`
- [ ] `AWS_S3_BUCKET=butterfly-room-staging`
- [ ] `docker compose ... config --quiet`が成功
- [ ] appを先に起動し、`/up`が200
- [ ] app確認後にworkerを起動
- [ ] app/workerのコンテナ名とimage名が本番と衝突しない
- [ ] `db:prepare`とステージングseedが成功し、本番データをコピーしていない

## 外部送信事故防止

- [ ] Basic認証なしで401、正しい認証で200
- [ ] `/robots.txt`が全クロールを拒否
- [ ] HTMLとレスポンスヘッダーに`noindex, nofollow`
- [ ] GTM script、noscript、conversion eventが出力されない
- [ ] メールのTo/Cc/Bccが承認済みredirect先へ置換され、件名に`[STAGING]`
- [ ] SMSがmockでAWS SNSへ送信されない
- [ ] Stripeがtest keyとステージングWebhook secretだけを使用
- [ ] S3 uploadがステージングbucketだけへ保存
- [ ] 新規IVS Stage名が`br-staging`で始まり、`app=butterfly-room`、`env=staging`、`store_id`、`booth_id`タグを持つ
- [ ] 既存本番IVS Stage ARNをDBへ設定していない

## 運用

- [ ] systemd app serviceの手動start/stopを確認
- [ ] 月次serviceをステージングDBで手動確認
- [ ] 月次timerは承認まではdisabled
- [ ] timerの`Persistent=false`を確認
- [ ] EC2停止中はtimerが動かないことを運用担当へ共有
- [ ] ログに秘密値、メール本文、認証情報が出ていない
- [ ] CloudWatch alarm、ログ保持、バックアップ方針を別途決定
