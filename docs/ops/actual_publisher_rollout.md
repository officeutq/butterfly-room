# 実配信者記録の有効化・復旧（#1288）

2026-09-15。対象は#1280。旧履歴は[固定一覧による作成者X補完](../design/legacy_publisher_backfill.md)へ統一する。過去IVSからの人物調査・専用権限追加は不要。今後の配信成功時の照合は継続する。

## 現在の適用状況

| 項目 | 状態 |
| --- | --- |
| 配信制御・人物表示・消化・集計・補完のコード | 各PRで統合済み、#1288で連携確認 |
| 共通有効化 | stagingは9月15日にtrueへ変更し、app・workerを同じ版で再起動済み。本番は未変更・無効 |
| 本番・stagingのDB調査 | stagingは新列導入・補完済み。本番は9月15日10時台の再確認で新列未導入、live/away=0。適用直前にも再確認する |
| 旧履歴の適用 | ローカル62件・staging12件を適用済み。本番は未適用。restoreの実施確認はtest DBのみ |
| ローカル固定一覧 | `tmp/publisher-backfill-local-20260914.json`。元の履歴・金額・通知と対象外672件の不変を確認。基準時刻・SHA・結果は補完手順に記録済み |
| 実環境の固定一覧 | stagingは下記の固定一覧を適用済み。本番は新列導入後に作成する |
| 実カメラ／マイク／画面加工 | stagingでブラウザーの模擬カメラ・音声と実DeepAR／実IVSを使用。物理カメラ／マイク・Banubaは未実施 |

2026-09-15 09:53:59 JSTにstagingのDBを再度読み取り確認した。新列未導入、終了済み開始あり12件・未開始準備2件、live/away・消化台帳・消化通知は0。結果は`tmp/issue1288-inventory-staging.json`。有効化前の確認として扱い、デプロイ後の固定一覧・適用結果とは分ける。

## 有効化する順序

1. 対象環境、デプロイするGit commit、DB接続先とバックアップを確認する。実施時刻と実行コードを記録する。アプリとworker（ジョブ実行プロセス）が同じ版・フラグを使うようにする。
2. 切替中の配信開始を停止し、`script/inventory_legacy_publishers.rb`を期待DB名付きで実行する。live/away=0、未終了不整合なしを確認する。前提外なら勝手に終了・人物補完せず判断へ戻す。準備のみは残す。9月14日の調査結果だけで現在も0と判断しない。
3. アプリのIVS権限を確認する。既存のCreateStage・TagResource・CreateParticipantToken・DisconnectParticipantに加え、同じアプリStageにGetStage・ListParticipants・GetParticipantが必要。タグ・環境の範囲を維持する。調査用Stageの権限があることをアプリStageの権限証明にしない。
4. 新しい全経路のコードとDB migrationを同じデプロイで導入する。旧準備を終了・一括更新しない。新列追加のmigration自体で旧履歴を補完しない。全消費側が揃った版でフラグをtrueにし、古いプロセスが残らないよう再起動する。
5. 同じ接続先・同じ実行版で終了済み旧履歴の`plan`を作成し、対象ID・X・開始終了・消化金額・除外理由・SHAを確認する。確認した固定一覧だけを`apply`する。開始記録なし等の除外は補完しない。ローカルは既存固定一覧を使い、基準を更新して件数を増やさない。
6. 適用件数／除外・競合件数を保存する。元のX・時刻・状態・台帳・消化／返却・保存済みコメントが不変であること、対象だけXの実績に移ることを照合する。画面・CastMetricsQueryの同期間の合計を確認する。
7. 新方式の開始→離席→本人再接続→消化→終了→履歴・集計をstagingで確認する。使う確認ユーザー・ブースとドリンクのテストポイントを明示する。本番で利用者のデータをテストのために変更しない。
8. `config/recurring.yml`の`retry_pending_publisher_disconnects`が毎分動き、`RetryPendingPublisherDisconnectsJob`のworkerとscheduler（定期ジョブの登録プロセス）のheartbeatが正常であることを確認する。切断待ちがある場合は該当人物・ブースの次回開始だけを保留する。
9. 開始を再開し、旧画面は再読込を案内する。実施commit・時刻・補完一覧SHA・件数・確認結果を本書へ追記してから#1288／#1280の残りを判定する。

コードの段階統合と実環境の二段階リリースは別。先行記録だけのリリース、全ブースの12時間待機、旧準備の一律終了は不要。切替作業中に旧・新の開始を混在させない。

## IVS権限の差分

stagingの`infra/terraform/environments/staging/iam.tf`の`UseTaggedStagingStages`へ`ivs:GetParticipant`を1項目追加した。Resource・app/envのタグ条件は維持し、ListStageSessions等の過去調査権限は加えていない。2026-09-15に稼働中の同名ポリシーを読み取り、不足を確認して下記の限定planだけを適用した。

`terraform fmt -check`・`terraform validate`は成功。既存ポリシーの参照先ARNから`DescribeSecret`で既存のGoogle Sheets認証Secret名を取得してplanへ渡した。Secret値は取得していない。

通常の全体planには、最新AMIへの更新によるstaging EC2とTarget Group登録の置換、メタデータ設定の変更が含まれた。今回の対象外なので**この全体planは適用しない**。インフラ構成の変更を今回へ追加しない。

例外的に`-target=aws_iam_role_policy.app`で権限だけの保存planを作成した。JSONを比較し、対象1件のupdate、追加Actionは`ivs:GetParticipant`だけ、他の全Statement・Resource・Conditionが不変であることを確認した。0追加・1変更・0削除。

- 適用したplan：`tmp/issue1288-staging-iam-only.tfplan`
- ファイルSHA-256：`8b2791276d7968c3c1f4020313299f2e2d654e7b95b7c661148ed479fef3c432`
- 対象ロール・現状との差・保存planのSHAを再確認し、0追加・1変更・0削除で適用成功。実アプリによる配信成功確定でも権限の利用を確認した。全体のNo changesを意味しない。

本番の実行ロール`butterfly-room-ec2-role`は別管理。9月15日に利用可能なデプロイ用ロールで管理ポリシー`ButterflyRoomIvsRealTimeStagePolicy`の本文を読み取り、既存の権限はCreateStage・GetStage・TagResource・CreateParticipantTokenであることを確認した。ListParticipants・GetParticipant・DisconnectParticipantが不足している。

追加用の[ポリシーJSON](actual_publisher_production_ivs_policy.json)は3権限だけを対象とし、東京リージョン・対象AWSアカウントのStage、タグ`app=butterfly-room`かつ`env=br`に限定する。`env=br`は本番で利用中の6 Stageのタグと、環境変数の未指定時の実装値を確認した結果であり、stagingのタグを流用しない。既存の管理ポリシーは変更しない。

2026-09-15、作業用IAMユーザー`butterfly-room-local`から本番ロールへの`iam:PutRolePolicy`がAccessDeniedとなり、追加は未実施。本番のコード・DB・有効化設定も未変更。過去履歴の調査権限ではなく、今後の配信開始・再接続・終了に使うアプリ実行権限である。

権限を持つ管理者の作業は、AWSコンソールのIAM→ロール→`butterfly-room-ec2-role`→許可を追加→インラインポリシーを作成→JSONに上記ファイルの全内容を貼り付け、名前`ButterflyRoomActualPublisherControl`で保存する。Codex側の作業用ユーザーへIAM管理権限を増やす必要はない。追加後にこちらで本文・実行ロールからの利用を確認し、バックアップ→コード・新列導入→固定一覧の確認・補完→有効化→検証へ進む。

## 2026-09-15 staging適用記録

- 初回コード`6a23393137d938f04a9a2f52ffa1a2d0d3b8b78f`。配信中・離席中・直近視聴者0を再確認し、app・workerを停止して2件のmigrationを実施した。未開始の準備2件は維持。
- DB単体バックアップ`/opt/butterfly-room/backups/issue1288-20260915/before.dump`を作成し、`pg_restore --list`成功。386,729 bytes、SHA-256 `52cd54f1919fe1ff8e01b5c0aab15d00c652795028b705cbda91dc19727aca82`。同じディレクトリの`env.before`とともに権限600。共有RDS全体の復元は行っていない。
- 固定一覧は同ディレクトリの`manifest.json`、SHA-256 `2e680cad391341eaddd6371fbd25f6ef492975abc109782f412e4dc3c2175716`、基準時刻2026-09-15 01:09:35.886426 UTC。ID 1・3〜13の12件だけをXへ補完し、`applied=12`、失敗・競合なし。ID 2・14は`not_ended`として除外。
- 前後比較で元の14行のX・状態・開始終了・更新時刻・現在参照・台帳、および元の消化通知が不変であることを確認。補完後の元データの個人実績合計は0pt・18秒。比較記録は`tmp/issue1288-staging-after.json`。
- 初回app／worker起動は01:10:45／01:10:55 UTC。HTTPS `/up`は200。毎分の`RetryPendingPublisherDisconnectsJob`登録、複数回の完了、全worker系heartbeat更新、当該ジョブの失敗0を確認した。
- 検証専用の店舗14・ブース4／5・ユーザー5名、テストポイント1,000ptを使用。実利用者の履歴・金額を検証目的で更新しない。検証履歴を物理削除しない。
- 準備プレビューと即時開始の二重初期化を修正し、コード`e92d55526b89e1fb905aca1388d3ad8b2f4d89f9`へ再デプロイ。image `sha256:96b856f7b532b74d1da027edfa31b044ad9b86e8c5f75fa45532ff8218a9263a`。app／workerのソースSHAとHTTPS 200を確認。再起動中の一時502は起動後に解消。
- 修正版の実ブラウザー確認は01:30〜01:32 UTCに成功。準備直後の開始→視聴側の映像・音声受信→他者・本人別ブースの開始拒否→離席・復帰→再読込による再接続→古い終了要求拒否→本人だけの消化・コメント管理→終了・返却→リザルト・履歴・共有・集計を確認。X=20、Y=21、Z=22で、準備16のXを保持してYを記録し、再接続前後のY・初回開始時刻が一致。新旧参加者IDは別、終了後の未解放接続0。
- 修正版で100pt消化・100pt返却、予約残高0。前の確認分も含む検証店舗の売上は200pt、テスト残高は800pt。売上台帳・消化通知・個人集計はY。検証スクリプトの共有確認は自動転送後の画面ではなく、転送前のHTTP本文にあるOGメタ情報を確認するよう修正した。
- 実行結果`tmp/issue1288-staging-browser-result.json`、画面`tmp/issue1288-staging-live.png`・`tmp/issue1288-staging-result.png`。合成デバイスによる確認であり、物理カメラ／マイクの確認を代替したとは扱わない。修正版のCIは[34917239330](https://github.com/officeutq/butterfly-room/actions/runs/34917239330)でquality・testとも成功。
- 検証後、専用2ブースを`CloseAndArchiveService`で閉鎖し、専用店舗を非公開・5ユーザーを利用停止・ドリンクを無効化した。準備17を正規終了し、終了済み配信15／16・接続4件・台帳200pt・返却記録・残高800ptを保持。IVSの接続中参加者0、DBのlive/away・切断待ち・未解放接続0を確認。結果は`tmp/issue1288-staging-cleanup-result.json`。元の未開始準備2件には触れていない。

## 失敗時の確認と回復

| 表示／状態 | 操作と確認 |
| --- | --- |
| 開始結果不明 | 同じrequest_idで状態確認。確定済みなら本人復帰、未確定なら同じ要求の取消。別IDの発行を連打しない |
| IVS照会不能・属性不一致 | 対象Stage・セッション・保存した参加者IDを確認。空きやXの配信と推測せず、正常な別対象まで止めない |
| 終了後の切断待ち | DB ended・返却済みを保持し、画面の再確認／定期ジョブで保存した参加者だけ再切断。終了・返却・売上を再実行しない |
| 通知失敗 | 保存済みコメントIDの`NotifyDrinkConsumptionJob`だけ再実行。消化APIを再実行しない |
| 補完途中の停止 | 同じ固定一覧・SHAでapplyを再開。件数を増やす再planを行わない |
| 補完の復旧 | 同じ一覧でrestore。適用後値が一致する行だけ新列を戻す。変更済み行は上書きしない |

エラー記録にはrequest_id・世代・participant_id・session_idと例外クラスを使い、配信用トークン・認証情報を出力しない。ジョブ失敗とDBの`disconnect_pending`件数／最古時刻を確認する。キュー投入失敗でも毎分の回収で残った切断待ちを扱う。

## 切り戻し

フラグをfalseに戻すと人物表示・個人集計も旧X基準へ戻るため、稼働中に単に変更しない。開始を止め、新方式で稼働配信を終了し、切断待ち・未解放の開始権を0にしてから、旧経路への切替を判断する。履歴のY・接続履歴・台帳を削除せず、DB migrationのdownを通常の切り戻しに使わない。

旧履歴のrestoreとアプリ切り戻しは別操作。補完の取り消しだけでは新方式で記録した配信は戻らない。過去の記録をXへ一括置換して旧コードに合わせない。
