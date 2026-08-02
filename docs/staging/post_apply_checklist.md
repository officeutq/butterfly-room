# ステージング構築後チェックリスト

## 現在の環境で確認済み（2026-08-02）

### AWS resource

- [x] staging EC2は`t3.micro`、Amazon Linux 2023、暗号化gp3 20GiB
- [x] EC2にElastic IPがなく、IMDSv2必須、CPU creditはstandard
- [x] EC2 security groupの3000/tcpはALB security groupからのみ許可
- [x] staging S3はpublic block、owner enforced、SSE-S3、versioning、CORSを設定
- [x] Target Groupはport 3000、`/up`、matcher 200、deregistration 300秒、stickiness off
- [x] HTTP staging host ruleだけがHTTPSへ301 redirect
- [x] HTTPS staging host ruleだけがstaging Target Groupへforward
- [x] 本番listener default actionは未変更
- [x] ACM certificateはISSUEDでHTTPS listenerへ追加済み
- [x] `staging.butterflyve.jp` Aliasは既存ALBだけを指す
- [x] apply後Terraform planは`No changes`
- [x] staging EC2は現在停止中
- [x] アプリ未配置のためTargetはunhealthy（現段階の想定どおり）

### DB分離

- [x] PostgreSQL 18系clientでTLS接続を確認
- [x] `butterfly_room_staging_user`を制限属性で作成
- [x] `butterfly_room_staging`をstaging user ownerで作成
- [x] staging userでstaging DBへ実接続
- [x] staging DB `CONNECT` / `TEMPORARY`がtrue
- [x] staging `public` schema `USAGE` / `CREATE`がtrue
- [x] 管理ユーザーの一時membershipが残っていない
- [x] production DBからstaging userの`CONNECT` / `TEMPORARY`を分離
- [x] staging userによるproduction DBへの実接続拒否を確認
- [x] production app roleの`CONNECT` / `TEMPORARY`を維持
- [x] `rdsproxyadmin`のproduction `CONNECT`を維持
- [x] 本番Railsの既存接続とservice正常性を確認

## アプリ配置後に確認

- [ ] `.env.staging`がmode 600でGit管理外
- [ ] `DATABASE_URL`のDB名が`butterfly_room_staging`
- [ ] `AWS_S3_BUCKET=butterfly-room-staging`
- [ ] `docker compose ... config --quiet`が成功
- [ ] `db:prepare`が成功
- [ ] staging seedが成功し、本番dataをコピーしていない
- [ ] appを先に起動し、`/up`が200
- [ ] app確認後にworkerを起動
- [ ] app/workerのcontainer名とimage名が本番と衝突しない
- [ ] Target Groupがhealthy

## 外部送信事故防止

- [ ] Basic認証なしで401、正しい認証で200
- [ ] `/robots.txt`が全crawlを拒否
- [ ] HTMLとresponse headerに`noindex, nofollow`
- [ ] GTM script、noscript、conversion eventが出力されない
- [ ] mailのTo/Cc/Bccが承認済みredirect先へ置換され、subjectに`[STAGING]`
- [ ] SMSはmockでAWS SNSへ送信されない
- [ ] Stripe test keyとstaging Webhook secretだけを使用
- [ ] S3 uploadがstaging bucketだけへ保存
- [ ] 新規IVS Stage名が`br-staging`で始まり、staging tagを持つ
- [ ] 既存本番IVS Stage ARNをDBへ設定していない

## 運用

- [ ] systemd app serviceの手動start/stopを確認
- [ ] 月次serviceをstaging DBで手動確認
- [ ] 月次timerは承認までdisabled
- [ ] timerの`Persistent=false`を確認
- [ ] EC2停止中はtimerが動かないことを運用担当へ共有
- [ ] logに秘密値、mail本文、認証情報が出ていない
- [ ] CloudWatch alarm、log retention、backup方針を別途決定
