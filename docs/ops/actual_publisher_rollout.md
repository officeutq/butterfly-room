# 実配信者記録の有効化・復旧（#1288）

2026-09-15。対象は#1280。旧履歴は[固定一覧による作成者X補完](../design/legacy_publisher_backfill.md)へ統一する。過去IVSからの人物調査・専用権限追加は不要。今後の配信成功時の照合は継続する。

## 現在の適用状況

| 項目 | 状態 |
| --- | --- |
| 配信制御・人物表示・消化・集計・補完のコード | 各PRで統合済み、#1288で連携確認 |
| 共通有効化 | `ACTUAL_PUBLISHER_CONTROL_ENABLED`既定false。実環境でtrueにしていない |
| 本番・stagingのDB調査 | 9月14日の観測は新列未導入、live/away=0。直前の再確認が必要 |
| 旧履歴の適用 | ローカルは9月15日に固定62件へ適用済み。staging・本番は未適用。restoreの実施確認はtest DBのみ |
| ローカル固定一覧 | `tmp/publisher-backfill-local-20260914.json`。元の履歴・金額・通知と対象外672件の不変を確認。基準時刻・SHA・結果は補完手順に記録済み |
| 実環境の固定一覧 | 新列導入後、書き込みのないplanを同じDB接続設定で作成する |
| 実カメラ／マイク／画面加工 | 未実施。合成映像による実IVS検証と区別 |

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

stagingの`infra/terraform/environments/staging/iam.tf`の`UseTaggedStagingStages`へ`ivs:GetParticipant`を1項目追加する。Resource・app/envのタグ条件は維持し、ListStageSessions等の過去調査権限は加えない。2026-09-15に稼働中の同名ポリシーを読み取り、不足を確認した。Terraform変更はコードのみで、AWSへの適用はまだ行っていない。

`terraform fmt -check`・`terraform validate`は成功。既存ポリシーの参照先ARNから`DescribeSecret`で既存のGoogle Sheets認証Secret名を取得してplanへ渡した。Secret値は取得していない。

通常の全体planには、最新AMIへの更新によるstaging EC2とTarget Group登録の置換、メタデータ設定の変更が含まれた。今回の対象外なので**この全体planは適用しない**。インフラ構成の変更を今回へ追加しない。

例外的に`-target=aws_iam_role_policy.app`で権限だけの保存planを作成した。JSONを比較し、対象1件のupdate、追加Actionは`ivs:GetParticipant`だけ、他の全Statement・Resource・Conditionが不変であることを確認した。0追加・1変更・0削除。

- 適用候補：`tmp/issue1288-staging-iam-only.tfplan`
- ファイルSHA-256：`8b2791276d7968c3c1f4020313299f2e2d654e7b95b7c661148ed479fef3c432`
- 未適用。実施前に保存planの内容・対象ロール・現状との差を再確認する。全体のNo changesを意味するplanではない。

本番の実行ロールは別管理のためstaging変更を流用しない。読み取りロールは本番の管理ポリシー本文を取得する`iam:GetPolicy`が許可されておらず、本文の確認は未完了。これは過去履歴の調査ではなく、新方式有効化前の実行権限確認として残す。

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
