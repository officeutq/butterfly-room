# 配信接続の再試行・終了結果の検証（#1336 / #1340）

2026-09-17。変更前はmain `1a9faaa`。以下はローカルのテストDBと代替AWS応答による検証であり、ステージング・本番への反映、実機や実IVSでの確認を意味しない。

## 実装の順序

| 子Issue | PR / 対象コミット | 内容 |
| --- | --- | --- |
| #1337 | #1341 / `e0809cb` | 切断上限、予定・回数・最終失敗、開始権、エラーログ |
| #1338 | #1342 / `593206c` | 開始確認の有限再試行、同じ要求の復旧・取消、最終失敗の記録 |
| #1339 | #1343 / `17fc82b` | 終了結果の確認、リザルト表示、強制終了通知、専用再確認ボタンの撤去 |
| #1340 | 本文書を追加したPR | 通信前の試行予約、応答保存障害・重複処理、対象を限定した運用復旧と横断検証 |

各PRは直前のPRを取り込み先にした連続した変更。#1341→#1342→#1343→本PRの順で取り込む。実装時点では環境へ未反映だったが、2026-09-17に利用者の指示を受け、`5dadac4`を[ステージングへ反映](../ops/publisher_retry_staging_verification.md)した。マージ・本番への反映は行っていない。

## 自動テストで確認する境界

| 対象 | 確認内容 | 主なテスト |
| --- | --- | --- |
| 開始確認 | 初回・追加各回の成功、3回後の停止、同じ要求の状態確認、成功済みの取消禁止、古い画面・世代の遅延応答 | `ivs_publisher_lifecycle_test.cjs`、`publisher_confirmation_failure_test.rb`、`publisher_connections_test.rb` |
| 切断 | 初回＋3回、0.5秒・1秒・2秒、予定前の重複実行、上限後のジョブ・旧入口による再開禁止、旧4回以上の記録 | `disconnect_publisher_connection_service_test.rb` |
| DB・外部通信 | 外側transaction（DBの一連処理）取消時にAWSを呼ばない。通信前の予約を確定し、4回とも応答保存が失敗しても5回目を送らない | 同上、`publisher_connection_concurrency_test.rb` |
| 複数操作 | 重複ジョブ、2端末の復帰、開始と取消、終了と閉鎖・退会、同一人物の複数ブース、アカウント・リージョンの切断枠 | 同上、`publisher_reconnection_test.rb`、`publisher_ending_test.rb` |
| 通常終了 | 手元の映像・音声停止、同じ終了要求の有限再確認、終了結果不明での成功遷移禁止、終了・返却の重複防止 | `ivs_publisher_lifecycle_test.cjs`、`publisher_ending_test.rb` |
| 強制終了・リザルト | 同じセッションの送信だけ停止、別セッションに影響しない、切断待ちと最終失敗、遅い旧画面応答の無視、認可付きGETは切断しない | `publisher_result_test.cjs`、`publisher_ending_test.rb` |
| 実配信者と消化 | 実配信者を維持し、準備者と配信者の区別、本人だけの消化、終了時の未消化返却 | `publisher_full_flow_test.rb`、既存の配信・消化テスト |
| ログ | 最終失敗の要求UUID・人物・店舗・セッション、通常再実行での重複抑止、秘密情報の除外、一般ユーザーの閲覧拒否、保存障害の代替記録 | `disconnect_publisher_connection_service_test.rb`、`publisher_confirmation_failure_test.rb`、`error_subscriber_test.rb`、`system_admin_logs_test.rb` |
| 運用復旧 | 既定は表示のみ、環境・DB・保存済み対象の一致、失敗しても回数を戻さず、成功時だけ解放、終了・人物を再更新しない | `publisher_disconnect_runner_test.rb`、`disconnect_publisher_connection_service_test.rb` |

AWS SDK（AWSを呼ぶライブラリ）の切断クライアントは`retry_limit: 0, max_attempts: 1`、接続・読込の期限は各5秒。テスト用クライアントで設定が受理されることを確認した。実AWSの呼出回数・通信時間を実測した結果ではない。同じDBの切断枠は0.25秒単位で、別DBの環境や運用ツールとは共有しない。

## ローカル実行方法と結果

全体テストでは既存の旧仕様テストも含むため、ローカルの`.env`から配信制御の有効化を引き継がず、既定の無効状態に合わせる。今回の配信制御テストは個別に有効化し、AWSを代替応答へ差し替えて実行する。開発用DBで実行しない。

```powershell
docker compose exec -T -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432/butterfly_room_test -e ACTUAL_PUBLISHER_CONTROL_ENABLED=false -e PARALLEL_WORKERS=1 app bundle exec rails test
npm run test:js
docker compose exec -T app bundle exec rubocop
docker compose exec -T app bundle exec brakeman --no-pager
git diff --check
```

Rails全体は1,655件・14,626 assertions（検証）成功、失敗・エラー・スキップ0件。JavaScriptは200件成功。RuboCopは713ファイルで指摘なし。Brakemanは警告なし。`git diff --check`も成功した。

運用runnerの出力捕捉は並列実行時にも入れ子にしない。関連64件を2プロセスで実行し、464検証・失敗／エラー0件を確認した。

代替応答の試験データはテストDBだけを使い、実Stage（AWSの配信ルーム）や開発環境の配信接続に故障状態を作っていない。

## 実機・実AWSで残る確認

以下は**未実施**。PC／スマートフォンそれぞれでキャスト・店舗管理者・システム管理者を対象に確認する。以前の#1277等の実機結果を今回変更部分の確認済みとして転用しない。

1. 準備から開始し、映像・音声が視聴側へ届く。通常終了で送信が止まり、リザルトへ移る。
2. 別ブラウザーから強制終了し、配信側への通知・送信停止・リザルト遷移、視聴側の終了を確認する。
3. 再接続・開始取消後に、正常な次の開始ができる。別タブ・再読込・再ログインで未確認接続の上限を戻せない。
4. 代替応答を使用できる隔離した検証環境で、開始確認・切断の各再試行成功と上限到達を確認する。再試行中・最終失敗・終了結果不明の表示を区別する。
5. システム管理者のエラーログで対象を照合し、[運用復旧手順](../ops/publisher_retry_recovery.md)で保存済み接続1件だけを復旧する。履歴・実配信者・返却に変化がなく、次の開始制限が解除されることを確認する。

実施時は対象コミット・環境・役割・端末・ブラウザー・確認時刻・結果を追記する。実利用者の配信へ障害を注入しない。終了通知とAWS切断の両方が失敗する場合の即時停止は保証せず、新たな配信継続監視は追加していない。

#1340は上記の未実施項目が残るため、この文書追加だけでDoneにしない。
