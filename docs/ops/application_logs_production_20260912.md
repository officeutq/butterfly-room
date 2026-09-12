# ログ機能を含む最新mainの本番反映・確認結果

## 結果と反映対象

2026-09-12、ユーザーの本番反映依頼により、依頼時点の最新main `0879b0a8a196445f0d0d9d97b808eb9646e56e12` を本番へ反映した。
[ステージングで検証したmain](../staging/application_logs_verification_20260912.md) `3e5b583` との差分は文書2件のみで、実行用コードに差分はない。
対象mainの[GitHub CI（自動検証）](https://github.com/officeutq/butterfly-room/actions/runs/34672156517)は成功済み。本番確認でアプリの追加修正は発生しなかった。

| 項目 | 記録 |
| --- | --- |
| URL | `https://butterflyve.jp` |
| 反映前 | main `f849dc424fadcd86f9e4f6afc3e361748120fb4c` |
| 反映後 | main `0879b0a8a196445f0d0d9d97b808eb9646e56e12` |
| 配置先 | `/home/ec2-user/apps/butterfly-room` |
| 稼働設定 | 既存の`docker-compose.production.yml`と`.env.production`、`RAILS_ENV=production`、`APP_ENV`未設定 |
| DB | `butterfly_room_production`、接続ユーザー`postgres` |
| 実行環境 | Ruby 3.3.12、Rails 8.1.2 |
| イメージ | `butterfly_room:main-0879b0a`、稼働タグ`butterfly_room:prod` |
| イメージID | `sha256:b92d53d173360f208e0edf875124db0dd48b31da4fe5e6776282b66302ed1476` |
| アプリ開始 | 2026-09-12 13:33:47、日本時間 |
| worker（非同期処理）開始 | 2026-09-12 13:34:09、日本時間 |
| 機能確認終了 | 2026-09-12 13:36:41、日本時間 |

最新main全体を対象としたため、ログ機能に加え、同じmainに含まれるプロフィール・アカウント編集の画面、ブース導線の変更も反映している。
それらを含むステージング確認とCIの成功を反映判断の根拠とした。

## 反映前確認と手順

- 本番EC2、既存のComposeプロジェクト`butterfly-room`、稼働イメージ、実接続DB名を照合。
- 追跡ファイルの変更はなし。既存の未追跡バックアップ・画像調査ファイル等7件と環境ファイルは、反映前後でSHA-256を比較して保持を確認。
- DBサーバー全体の接続は31／上限80。RDSの状態はavailable、自動バックアップ保持7日、確認時の最新復元可能時刻は13:26:17（日本時間）。
- DB上のliveセッション6件はいずれも以前の日付で、配信開始日時未設定、ブースはstandby（配信準備中）。直近10分の視聴在室更新・コメントは0件。切り替え直前にも新しい在室記録・配信開始がないことを確認した。これらの業務状態は変更していない。
- 現行イメージを`butterfly_room:rollback-before-logs-20260912`として保持。
- mainを早送り更新し、現行イメージを基に最新mainの`app`・`config`・`db`・`lib`・`script`を組み込み。実行用ソースのSHA-256一致を確認し、`npm run build:css`と`assets:precompile`に成功。
- 新イメージで実接続DB、ログ収集の初期化、未適用migrationが`20260912000000`だけであることを確認。
- `bundle exec rails db:migrate`でログテーブル2つ・索引・制約を追加。migrationは約0.10秒。既存データの変換、seed再投入、DB初期化は実施していない。
- 既存Compose設定の`up -d --no-deps --no-build --force-recreate`でアプリを切り替え、内部`/up`の成功後にworkerを切り替えた。両コンテナのイメージIDと実行用ソースの一致を確認。

依存ファイル、`Dockerfile.production`、Ruby指定、`public`、`vendor`、`bin`、本番Compose設定に差分がなく、追跡ファイルの削除もないことを確認してから上記の差分ビルドを行った。
ステージングと同じ方法で、依存パッケージ・ベース環境の更新は行っていない。
既存のSass非推奨警告とFilePondの静的CSS参照に関するビルド時警告は出たが、ビルドは成功。FilePondのCSS2件は本番HTTPSで200、画面が読み込むCSS・JavaScriptにも取得失敗はなかった。

## 本番での最小確認

サーバー側5項目、Chromiumによる実ブラウザー・HTTPS側11項目に成功。

- ログテーブル・migration適用、`Logs::ErrorSubscriber`の登録、ErrorLog専用接続プール最大2接続を確認。
- 一時的なシステム管理者1件と非公開の検証用Store 1件を作成。実HTTPSの`PATCH /admin/stores/:id`で店舗名を1回だけ更新し、更新履歴がちょうど1件作成された。
- DBの店舗名と履歴の変更前後値、実行者、対象、店舗ID、リクエストID、処理元`web`が一致。
- `Rails.error.report`で`ProductionLogVerification`という確認専用の事象を1件記録。重要度は`info`、処理側で捕捉済みとして報告したもので、実障害ではない。稼働アプリでの例外発生や失敗ジョブ投入は行っていない。
- システム管理者のダッシュボードからログ画面へ移動でき、更新・エラー各1件の検索、詳細、変更前後値を表示。未認証での両一覧アクセスはログインへ誘導。
- 最新mainのプロフィール編集・自身の詳細画面も200で表示。読み込むCSS・JavaScriptにHTTPエラーはなし。
- 検証用アカウントは論理削除し、パスワードも再生成して検証時の認証情報とセッションを無効化。認証情報は作業記録から除去した。

確認に使用したStore IDは30、change_logs IDは1、error_logs IDは1。
Store名は「【検証終了・非公開】ログ機能 本番確認 2026-09-12」で、非公開のまま保持。履歴は物理削除していない。
メール・SMS・決済・配信開始等の外部処理は検証で実行していない。
負荷試験、業務更新取消、ログ保存の故障試験、非同期処理の意図的失敗、アーカイブ適用はステージングでの検証に留め、本番では再実施していない。

## 終了時の状態と運用上の残事項

- アプリ・workerは同じイメージで稼働、再起動回数0。内部・公開HTTPSの`/up`が200、ALB（負荷分散装置）の本番対象がhealthy。
- 切り替え後のコンテナ通常ログで`error_log_write_failed`とHTTP 5xxの記録は0件。意図した確認用1件以外のエラーログは0件。
- DB接続は共有DBサーバー全体36／上限80、うち本番16。DB容量28,669,631バイト。ログは各1件、各テーブルの索引等を含む使用量は131,072バイト。
- workerのWorker・Dispatcher・Supervisor・Schedulerの4種類が直近の稼働通知を更新。未完了ジョブは反映前後とも3件、実行中の取得済みジョブは0件。
- 本番ホストのディスク空きは反映前約1.9GB、終了時約1.8GB（使用率95%）。今回作った約58MBの一時ビルド展開先は除去し、照合用一覧・ビルド定義・確認結果だけを`/home/ec2-user/apps/logs-production-deployment-20260912`へ保持。過去のイメージやバックアップは削除していない。

ディスク空きは少ないため、次回の更新前、特に依存環境の全面ビルド前には容量を確保する。今回の少量確認はピーク負荷・長期運用の性能保証ではない。
ログの保持方針と手動アーカイブは[種類別ログ設計](../design/application_logs.md)を参照する。

## アプリの復旧手順

復旧用イメージは`sha256:df715c48e6aafe2ef02742b5cf3b25cd33ef8aed704d555c68cf244d616d2727`。
本番配置先・Compose設定を確認した上で以下を実行し、起動・公開URLを確認する。

```bash
cd /home/ec2-user/apps/butterfly-room
docker tag butterfly_room:rollback-before-logs-20260912 butterfly_room:prod
docker compose -p butterfly-room -f docker-compose.production.yml up -d --no-deps --no-build --force-recreate app worker
```

今回は復旧操作は不要だった。記録済み履歴を守るため、旧アプリへ戻す場合もログテーブルを削除するmigrationの取消は行わない。旧版で記録が停止した期間は運用記録に残す。
