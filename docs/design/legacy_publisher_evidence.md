# 旧配信の実配信者に関する証拠調査（#1287）

2026-09-14時点の途中結果。**DB調査は実施済み、IVS履歴の調査は権限不足で未完了。証拠補正・作成者補完とも実環境へ未適用。** #1287と親 #1280 は完了していない。

## 調査の区別

準備作成者X、ブース担当者Z、実配信者Yを区別する。#1289の `legacy_creator_backfill` は合意した旧履歴の帰属方針であり、Yを立証する資料ではない。新しい `ivs_verified` と、後から証拠で補正する `evidence_backfill` とも区別する。

過去の誤帰属をまだ確認していない段階で「本番で別人の売上になっていた」と断定しない。取得不能・資料なし・複数候補・矛盾は別の調査結果として残し、XやZを実配信者と推定しない。

## 読み取り専用のDB調査

`script/inventory_legacy_publishers.rb` をRails runnerで実行する。`PUBLISHER_AUDIT_EXPECTED_DATABASE` と接続DBを照合し、Repeatable Read + READ ONLY、SQL上限10秒を指定する。実配信者の新列を追加する前のスキーマでも使える。元のID・時刻・現在参照と、消化台帳の金額・件数、保存済み消化通知のID・投稿者・時刻を出力する。コメント本文・メール・任意のevidence・トークンは出力しない。

```powershell
docker compose exec -T -e PUBLISHER_AUDIT_EXPECTED_DATABASE=butterfly_room_development app bin/rails runner script/inventory_legacy_publishers.rb
```

他環境では各環境の既存稼働コンテナにスクリプトを標準入力で渡した。コードのデプロイ、migration、テストデータ投入、既存データ更新は行っていない。新旧カラム・分類・誤接続拒否・DB非変更のテスト3件27検証が成功した。

| 2026-09-14の観測 | ローカル開発 | ステージング | 本番 |
| --- | ---: | ---: | ---: |
| 観測時刻（JST） | 17:26:51 | 17:24:26 | 17:24:22 |
| セッション総数 | 734 | 14 | 7 |
| 現在参照のある未開始準備 | 23 | 2 | 6 |
| 現在参照のない未終了 | 4 | 0 | 0 |
| DB上の配信中・離席中 | 0 | 0 | 0 |
| 開始記録のある終了済み | 62 | 12 | 1 |
| 開始記録のない終了済み | 645 | 0 | 0 |
| 消化台帳ポイント総額 | 636,701 | 0 | 0 |
| 保存済み消化通知 | 27 | 0 | 0 |
| 実配信者の新列 | 導入済み、未補完 | 未導入 | 未導入 |

本番の開始記録は2026-07-23のセッションID 5（ブース5、X=14、記録上158秒）。ステージングは2026-08-02のID 1と2026-09-01のID 3〜13で、Xはそれぞれ1・9。ID 2・14は未開始準備である。これらのXがYであることは未確認。両環境とも個人別ポイントへの補完影響は0だが、名前・配信時間には影響する。

ローカルの開始記録あり62件は消化ポイント25,301、開始記録なし645件は611,400。開始なしを未配信の証拠とせず、時刻を推定して補完対象へ混ぜない。ローカルには撮影用の架空Stage ARNを持つ記録もあり、実AWS参加の証拠と区別する。

ID別の結果は`tmp/issue1287-inventory-local.json`・`tmp/issue1287-inventory-staging.json`・`tmp/issue1287-inventory-production.json`に保持。これは調査結果であり、補正を適用する固定一覧ではない。後続の適用一覧は新列導入後の変更前値も含めて別途確定する。

## 利用可能な記録と限界

- 旧`Ivs::CreateParticipantTokenService`は認証した人物の`user_id`、アプリの`stream_session_id`、`role`を参加者属性に入れるが、発行しただけでは配信成功を証明できない。旧DBに参加者IDは保存していない。
- 共通の変更履歴は店舗・ブース編集を対象にし、配信開始成功の記録は含まない（[種類別ログ設計](application_logs.md)）。エラーログの実行者も失敗・操作の人物であり、配信成功の人物とは限らない。通常表示はエラー90日・更新365日、物理削除せずアーカイブ後も検索できる。
- 実DBで、配信セッション参照付きの変更／エラーログは3環境とも0件。ステージングのログは検証用の過去日付も含むため、最古日時を本番稼働期間と読み替えない。
- 本番・ステージングの現在のアプリコンテナ通常ログは、それぞれ2026-09-12 13:33:50／14:27:25 JST以降。今回の旧配信の日付を含まない。Dockerの`json-file`で、コンテナ個別の`max-size`／`max-file`指定は空、配置先の`log/`には`.keep`だけだった。別保管先や過去コンテナの完全な履歴を確認済みとは扱わない。

## IVSで確認する根拠

[ListStageSessions](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_ListStageSessions.html)でStage内のIVSセッションを列挙し、[ListParticipants](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_ListParticipants.html)と[GetParticipant](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_GetParticipant.html)で参加者属性を照合する。すべてのページを取得し、RailsのセッションIDとIVSセッションIDを混同しない。

[Participant](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_Participant.html)の`published`は、そのIVSセッション内で配信したことがあるかを表す。現在接続中かとは別で、単独ではアプリの配信期間内に配信した時刻まで確定できない。[ListParticipantEvents](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_ListParticipantEvents.html)の時刻付きイベントも使い、Stage・IVSセッション・参加者・アプリセッション属性・認証人物・対象期間を対応付ける。`firstJoinTime`だけを配信開始時刻に置換しない。

今回参照した公式の[監視ガイド](https://docs.aws.amazon.com/ivs/latest/RealTimeUserGuide/stage-health.html)と上記API文書からは、参加者履歴の固定保存日数の保証を確認できていない。「14日」等の別用途の値を保存期間として採用しない。実取得でどの日付まで戻れるかを記録し、API失敗・空一覧・Stage削除を「誰も配信していなかった」と扱わない。[EventBridge通知](https://docs.aws.amazon.com/ivs/latest/RealTimeUserGuide/eventbridge.html)には欠落・遅延・順序逆転があり得るため、通知なしだけで他の配信者を否定しない。

実取得した証拠を見て、単独の人物を裏付けられるケース、不明、複数候補・矛盾を分類する。証拠補正はその分類後に対象・根拠・変更前後・個人別影響を固定して実装・検証する。保存済み消化通知は種類と証拠を限定し、通常コメント・操作履歴は変更しない。現時点で補正値を仮定した汎用一括更新は追加していない。

## 調査再開に必要な権限

2026-09-14、以下の`ListStageSessions`が`AccessDeniedException`となった。

- 読み取り用ロール`butterfly-room-inventory-readonly` → 本番のStage `f9zeDOigmiyI`。
- ステージング用ロール`butterfly-room-staging-deployer` → Stage `g7TNL2OzqeB2`。

以前追加された検証用Stageの権限は、これらの旧Stageの履歴調査を許可するものではない。DB調査のために追加権限が必要だったわけではない。

追加案は [読み取り専用ポリシーJSON](../ops/issue1287_ivs_history_readonly_policy.json)。`butterfly-room-inventory-readonly`ロールに`ButterflyRoomIssue1287HistoryRead`というインラインポリシーとして追加すれば、一つの読み取り用プロファイルで調査できる。対象は開始記録がある旧配信の実ARN 11件（本番1・ステージング2・ローカル8）。作成・トークン発行・切断・削除・DB更新・IAM変更は許可しない。アプリ本体の実行権限変更とも別である。

IAMコンソールで「ロール」→`butterfly-room-inventory-readonly`→「許可を追加」→「インラインポリシーを作成」→JSON欄に上記内容を設定する案を用意した。調査終了後はこの追加ポリシーだけを削除できる。エージェントは権限を変更していない。

## 未完了の作業

1. 読み取り権限の追加判断後、IVSの保存範囲と実際の履歴を確認する。
2. 証拠で裏付けられた対象について、固定一覧による補正・中断再開・復旧を実装し、通常コメント・台帳等の非変更を検証する。証拠不足は不明のまま残す。
3. 実環境への適用は新列導入後に具体的差分を確認し、判断を記録する。現時点では3環境とも未補正・未補完。
4. #1288の全体検証・共通有効化へ進む。関連の店舗／ブース選択・招待Epicが未実装の場合は連携確認を未完了として残す。親 #1280 を先に閉じない。
