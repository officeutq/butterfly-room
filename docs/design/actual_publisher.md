# 実配信者の保存・配信制御・参照設計（#1280 / #1281）

基準：`f1f58ec`。2026-09-14、#1298の実測と、[終了失敗時の案Bの承認](actual_publisher_end_failure_decision.md)を反映した実装契約。**本書は目標仕様。アプリの有効化・移行実施済みとは扱わない。** X=準備作成者、Y=実配信者、Z=ブース担当者。配信権限者には店舗管理者・システム管理者を含む。

## 1. 固定する前提

- 準備は同じ `stream_session` を権限者が再利用する。Xを保持し、成功した配信だけにYを記録する。Zは担当表示のまま。
- Stageはブース固定。`stream_session.ivs_stage_arn` はブースのARNを保持する。視聴者起点・トークン要求起点のStage作成は行わない。
- 適用時のステージング・本番DBには配信中・離席中がないというユーザー指定を採用する。無停止の旧配信引継ぎ、先行記録だけのリリース、移行専用の12時間待機は不要。未配信の旧準備は維持する。
- トークン・参加者ID・アプリの配信セッション・IVSセッションは別物。[調査資料10・11節](legacy_publisher_migration_research.md)の実測を前提にし、外部確認失敗を空き扱いしない。
- IVS切断が失敗してもDB終了・未消化返却・閉鎖／退会は進める。切断を別途再試行し、該当人物・ブースの次の配信だけを確認完了まで保留する。履歴のYと初回時刻を保持する。
- 売上は消化確定分だけ。期間・率・丸め・店舗台帳・精算・未消化返却を変更しない。

## 2. D04：保存領域と共通参照（#1282）

### 2.1 配信セッション

`stream_sessions` に次を追加する。既存行の人物・状態・時刻を更新するデータ移行は含めない。

| 列 | 型・初期値 | 意味・更新者 |
| --- | --- | --- |
| `actual_publisher_user_id` | bigint、NULL可、usersへの外部キー | 初回配信成功時の認証済みY。通常の再接続・終了では変更しない |
| `actual_publisher_source` | string、NULL可 | `ivs_verified`（新方式）、`legacy_creator_backfill`（合意済み旧履歴補完）、`evidence_backfill`（証拠による補正） |
| `actual_publisher_recorded_at` | datetime、NULL可 | 上記人物を記録した時刻。初回配信時刻の `broadcast_started_at` と分ける |
| `actual_publisher_evidence` | jsonb、非NULL、既定 `{}` | 新方式は要求ID・参加者ID・IVSセッションID。補正は資料参照・対象一覧のハッシュ・変更前後。トークンやメール等は保存しない |
| `publisher_generation` | bigint、非NULL、既定0 | 配信制御の世代。発行・取消・終了時に進め、古い画面の操作を区別する |
| `current_publisher_connection_id` | bigint、NULL可、下表への外部キー | 準備の開始処理／現在の配信接続。成功実績のYとは別 |

人物・source・recorded_atは全てNULL、または全て設定の組合せに限定する。sourceは上記3値。人物を設定する行には `broadcast_started_at` が必要。`publisher_generation >= 0`。索引は実配信者、source、および未終了の実配信者の検索に付ける。既存の作成者必須制約は保持する。Yの退会は論理削除のため外部キーを維持する。

### 2.2 配信接続

`StreamPublisherConnection` / `stream_publisher_connections` を追加する。1行は1回の発行要求を表す。取消・終了後も行を物理削除しない。

| 列 | 型・条件 | 用途 |
| --- | --- | --- |
| `request_id` | uuid、非NULL、全体で一意 | ブラウザーが操作ごとに生成する要求ID。同じIDを別のセッション・人物へ流用しない |
| `stream_session_id` / `booth_id` / `user_id` | bigint、非NULL、各外部キー | 発行先と開始権所有者。boothはセッションの所属と一致させる |
| `generation` | bigint、非NULL、正数 | セッションの世代と対応 |
| `ivs_stage_arn` | string、非NULL | 発行時のStage。後の現在ブースや現在セッションから引き直さない |
| `ivs_participant_id` / `token_expires_at` | string / datetime、NULL可 | 発行応答から保存。両方NULLまたは両方設定 |
| `confirmed_at` | datetime、NULL可 | 当該要求の配信成功確認。セッションの初回時刻とは別 |
| `disconnect_requested_at` / `disconnect_reason` | datetime / string、NULL可 | 外部切断の意図。reasonは `cancel` / `replace` / `end` |
| `disconnected_at` | datetime、NULL可 | 保存したIDへの切断API成功を確認した時刻。leave・期限・詳細404で埋めない |
| `released_at` | datetime、NULL可 | この開始権を解放した時刻。取消や終了のDB完了だけでは解放しない |
| `disconnect_attempts` / `last_disconnect_error` / `next_disconnect_retry_at` | integer既定0 / string / datetime | 切断試行回数、例外クラス等の安全な理由、次回再試行時刻 |
| `created_at` / `updated_at` | datetime | 標準の記録時刻 |

`released_at IS NULL` の行について、user_idごとに1件、stream_session_idごとに1件の部分一意索引を設ける。ブース固定Stage内の参加者IDにも一意索引を設ける。終了済みでも切断未完了なら開始権を保持する。成功済み配信の再接続では、旧行解放と新行作成を同じトランザクションで行う。新発行が失敗した場合は旧行が開始権を保持し、同じYが再試行できる。

トークン文字列はDB・ログに保存しない。発行応答はトランザクション確定後だけブラウザーへ返す。発行後にDB保存が失敗したトークンをレスポンスへ出さないため、未記録のトークンを利用者が受け取る経路を作らない。

### 2.3 読み取りAPI

| API | 返す情報／条件 |
| --- | --- |
| `StreamSession#actual_publisher_user` | 保存されたY。空欄をXやZへ置換しない。過去セッションにも使用 |
| `StreamSession#actual_publisher?(user)` | userが存在し、保存済みYと一致する場合のみtrue。NULL同士を本人扱いしない |
| `StreamSession.actually_broadcasting_by(user)` | Y一致、開始時刻あり、未終了、status=live、booth.current一致、boothがlive/away。準備は含めない |
| `Booth#actual_publisher_user` | 現在セッションが上記の実配信状態ならY。それ以外はNULL |
| `StreamPublisherConnection.unreleased` | 開始処理・現在接続・切断待ちの開始権。本人配信中の判定に代用しない |
| `StreamPublisherConnection.disconnect_pending` | 切断要求あり・切断成功なし。終了済み・閉鎖済み・退会済みも含める |
| `StreamSession#publisher_recording_state` | `recorded` / `not_started` / `unknown` / `inconsistent`。下記D01のDB分類 |

これらのDB参照はIVS通信を行わない。人物不明と空きを同一視せず、実際の開始可否はD01の外部確認を含むServiceが判定する。

`publisher_recording_state` のRubyでの返却値はSymbol。終了時刻が欠落、または初回配信時刻より前の履歴は `inconsistent` とする。保存時はevidenceをJSONオブジェクトに限定し、切断要求日時と理由も両方NULLまたは両方設定に揃える。現在接続とセッション、接続と所属ブースの対応はモデルでも検証する。

## 3. D01：準備・不整合・配信成功

### 3.1 DB分類と外部確認が必要な場面

| 入力 | DB分類・扱い | 外部確認 |
| --- | --- | --- |
| 現在のstandby、未終了、開始時刻なし、Yなし | `not_started`。Xや新列空欄を理由に再利用拒否しない | 配信準備への入場・トークン発行前に対象Stageを確認。正常な情報閲覧では不要 |
| 別ブースに準備のみ | 本人配信中に数えない | 別準備の存在だけで全Stageを照会しない |
| Y・初回時刻・現在参照・live/awayが整合 | `recorded`。本人Yだけが再接続・状態変更可能 | 通常表示はDB。新トークン発行・成功確定時は確認 |
| 終了済み、Yあり | 履歴の `recorded`。現在の担当Zが変わっても人物を変えない | 履歴表示のための通信なし |
| 終了済み、Yなし | `unknown`。時刻なしだけでは過去の未配信を証明できない | 過去補正は #1287。通常表示で通信しない |
| live/awayなのに人物・時刻・現在参照が欠落／矛盾 | `inconsistent`。対象を空き扱いしない | 対象の確認へ進む。旧配信引継ぎを推測実装しない |
| 対象外の人物・接続、属性不一致、複数の配信者候補 | `inconsistent`相当の開始エラー | 根拠を保持し対象だけ拒否。Xやアクセスした人に補完しない |

準備・発行の外部確認は `Ivs::ParticipantSnapshotService` が担当する。GetStage → activeSessionIdがあればListParticipants全ページ → 必要な参加者のGetParticipant → GetStageを行い、前後で同じIVSセッションであることを確認する。全ページ取得前の成功判定はしない。対象Stageなし、ページ途中失敗、前後のID変更は確認不能。安定した空のStageは準備を許可する。参加者の `published` だけで現在配信中と決めず、接続状態と属性を合わせる。

対象Stageの別セッションの接続、他人の配信者接続、識別不能な接続を発見した場合は新しいトークンを発行しない。保存済みで切断意図がある対象はD03の再試行を行える。未知の接続をユーザーの承認なしに切断する復旧処理を追加しない。情報・履歴の閲覧や別の正常なブースは許可する。

### 3.2 成功確定

Web SDK 1.30.0の自分の `STAGE_PARTICIPANT_PUBLISH_STATE_CHANGED` が `published` になった時にだけ、要求IDと世代を開始確定APIへ通知する。`join()` のPromise完了だけでは通知しない。サーバーは認証、現在参照、世代、開始権、保存済み参加者ID、IVS詳細の `role=publisher`・`stream_session_id`・`user_id`、`CONNECTED/published=true` を照合する。

トランザクション内で、初回のみY・source=`ivs_verified`・recorded_at・初回broadcast_started_atを保存し、connection.confirmed_at・booth.live・last_online_atを整合させる。同じ要求の再確認は保存済み結果を返す。確定済みYや初回時刻を変更しない。再接続は同じYでのみ接続確認を更新する。

## 4. D02：開始権・要求・再接続

### 4.1 ServiceとAPIの契約

Controllerは認可・入力の読取・Service呼び出し・応答に留める。状態保存、ロック、外部処理、失敗回復はServiceへ置く。

| 操作／Service | 入力 | 成功時の結果 |
| --- | --- | --- |
| `Booths::EnterAsCastService` | booth、認証actor | 同じ準備を返す、または新規準備。Xの記録は新規時だけ |
| `StreamSessions::IssuePublisherConnectionService` | stream_session、actor、request_id、expected_generation | token、request_id、generation、participant_id、expires_at。準備のXと成功実績は変更しない |
| `StreamSessions::ConfirmPublisherService` | stream_session、actor、request_id、generation | 確定済みY・初回時刻・接続と現在状態 |
| `StreamSessions::PublisherStateService` | stream_session、actor、request_id | 自分の要求のissued/confirmed/cancel_pending/cancelled/ended/supersededと世代。トークン文字列なし |
| `StreamSessions::CancelPublisherConnectionService` | stream_session、actor、request_id、generation | 未確定だけ取消。確定済みならconfirmedを返す。切断失敗はcancel_pending |
| `StreamSessions::StatusService` | booth、stream_session_id、actor、request_id、generation、to_status | 本人Yのlive/awayだけ変更。standby→liveは開始確定へ集約 |
| `StreamSessions::EndService` / `ForceEndService` | stream_session、actor、expected_generation、通常／管理／既存自動処理の文脈 | ended_sessionとdisconnect_pending。人物・初回時刻は保持 |

新しい状態取得は `GET /cast/stream_sessions/:id/publisher_state`、取消は `POST /cast/stream_sessions/:id/cancel_broadcast`。発行・開始確定・状態変更・終了は既存URLを維持して識別情報を追加する。認証人物以外のuser_idや、任意のStage・参加者IDによる更新は受け付けない。

### 4.2 発行と競合

対象booth→stream_session→connectionの順にロックし、外部呼び出しを含む業務処理をServiceへ集約する。既存の退会処理の外側トランザクションを尊重する。複数対象はID順とし、DBの競合エラーを無制限に再試行しない。

未終了の本人配信と開始権の一意制約を両方確認する。同じYのA/B同時開始は一方だけが開始権を取れる。同じ準備のX/Yも同様。負けた発行要求は409で状態を返し、勝者を取り消さない。異なる要求のUUIDを既存要求へ読み替えない。

発行は現在世代一致を要求し、新しい世代・connection作成・参加者IDと期限の保存を同じトランザクションで確定する。トークンは確定後だけ返す。AWS応答消失や保存前失敗では文字列を利用者へ配布せず、未確定の開始権を残さない。保存済みIDがある場合はその記録を使用し、重複発行しない。

同じrequest_idの再送は保存済み状態を返す。トークン文字列は再取得できないので `token_already_issued` と現在状態を返し、同じブラウザーの回復処理が状態確認→旧IDの取消／切断→新UUIDで再発行する。確定済みなら再接続手順へ進む。遅れて届いた古いHTTP応答はクライアントの操作UUID照合で破棄する。

### 4.3 取消と再接続

未確定の開始取消は当該準備の既存終了権限を持つ人が、明示的な取消として実行できる。競合する発行要求の失敗処理として他人を自動取消しない。取消と確定が競合した場合、確定が先ならconfirmedを返し、取消が先なら世代を進めて遅い確定を拒否する。

取消は切断意図を保存し、保存したIDの切断成功後に開始権を解放する。同じ準備とXは保持する。失敗時はcancel_pendingを表示し、D03のジョブおよび「再確認」で再試行する。未参加でも切断できるため、トークン期限まで一律に待たない。

本人Yの再接続は初回時刻・人物・セッションを維持する。以前のIDを切断して、新世代・新UUID・新参加者IDを発行する。旧行解放と新行作成を同じトランザクションで確定する。途中失敗時は同じ対象で再試行可能にし、固定90秒等を置かない。DB保存が失敗し切断記録がロールバックしても、以前のIDへの重複切断は可能。別人はこの操作でYを引き継がない。

SDKの自然再接続は同じインスタンス・同じ要求のまま扱う。画面再読込や新インスタンスによる復帰は必ず上記手順。ブラウザーはDB確定の確認が終わるまでSDK参照を保持し、失敗時はleaveと当該要求の取消を実行する。単に参照をNULLへ捨てて成功／取消扱いにしない。

### 4.4 世代と画面

準備画面にはgeneration=0でも値を持たせる。発行時に世代を更新し、開始確定・離席・終了はその世代と要求IDを送る。管理者の終了・準備の終了・閉鎖フォームには表示時点のセッションIDと世代を持たせる。開始要求がまだない準備の終了も、世代0で可能。旧画面の識別情報なし要求は409で再読込を案内し、最新要求を勝手に割り当てない。

| HTTP／code | 画面・復帰 |
| --- | --- |
| 403 `forbidden` | 対象の権限がない。別対象の状態を変更しない |
| 409 `stale_publisher_request` | 「配信の状態が更新されています。画面を読み込み直してください」。状態を再取得する |
| 409 `publisher_in_use` | 本人の別配信、別人の配信、競合する開始処理を理由別に案内。所有者を推測しない |
| 409 `token_already_issued` | 上記の状態確認と新UUIDによる回復。無条件の重複発行なし |
| 409 `not_joinable` / `stage_mismatch` | 閉鎖・終了・現在参照・Stage不一致。対象を変えず案内 |
| 503 `publisher_state_unavailable` | 「配信状態を確認できません。再確認してください」。同じ対象の再確認ボタンを残す |
| 202 `publisher_disconnect_pending` | 取消は確認待ち。終了の場合は終了・返却完了を明示。切断だけ再試行 |

## 5. D03：終了・切断再試行（承認済み案B）

### 5.1 認可と呼び出し

| 経路 | 許可する人・条件 | 世代と結果 |
| --- | --- | --- |
| 未配信準備の通常終了・取消 | 現行の準備操作権限者。Xと異なるYも可 | 表示時点の世代。ID未発行の準備でも終了できる |
| 配信中・離席中の通常終了／状態変更 | 保存済みYかつ現在も配信権限がある人 | 現在要求・世代一致。Xという理由では許可しない |
| 管理者強制終了 | 管理店舗の管理者／システム管理者 | 対象セッション・表示時点の世代。実績を管理者へ付け替えない |
| 準備の手動閉鎖 | 既存の管理権限。配信中・離席中は先に終了が必要 | 準備を正規終了後に閉鎖。切断待ちは保持 |
| `CloseAndArchiveService` | 既存の所属解除／退会から認可済み対象を明示 | ロックして対象と世代を確保して終了。手動閉鎖と別の既存自動終了経路 |
| `RemoveCastService` | 本人キャスト／管理店舗管理者／システム管理者の既存条件 | 対象所属キャストのブースを終了・返却・閉鎖後に所属解除 |
| `WithdrawalService` | 既存の本人退会、最後の店舗管理者の店舗整理 | 最外側DBトランザクションの確定後に通知と切断ジョブ。外部切断はロールバックできない |

### 5.2 終了の順序・失敗

1. ロック下で認可・対象・世代を検証し、世代を進める。対象の未解放connection全てに切断意図 `end` を設定する。操作対象を別セッションへ切り替えない。
2. 保存した参加者IDへ同期切断を試す。成功したIDはdisconnected_at・released_atを保存する。失敗は理由を保持し、成功扱いにしない。
3. 同じDBトランザクションでセッションended・ended_at、対象boothのoffline・現在参照解除、未消化返却を確定する。Y・初回時刻・準備作成者は維持する。DB保存失敗なら返却もロールバックし、同じ要求から再試行する。
4. 最外側のDB確定後だけ終了通知・残高通知・切断ジョブを送る。通知失敗によって返却を再実行しない。既に終了済みの同じ対象への再試行は既存の結果と切断待ちを返す。
5. 切断待ちがあれば「配信の終了と未消化ドリンクの返却は完了しました。映像の切断を再試行しています」と案内する。閉鎖・所属解除・退会はDB成功なら続行する。

未配信準備で参加者IDがなく、外部の矛盾がない場合は接続記録を要求せず終了できる。旧準備を新列空欄だけで閉じ込めない。未知の旧接続が見つかった場合は移行前提の例外として対象を記録して判断を戻し、全Stageを削除しない。

### 5.3 再試行の保存と実行

`Ivs::DisconnectPublisherConnectionService` はconnection IDだけを受け取り、保存済みStage・参加者IDを使う。切断要求なし・解放済みは何もしない。人物の退会・ブース閉鎖後も記録された切断意図を処理できる。DB結果はその行に限定し、現在の接続へ読み替えない。

`DisconnectPublisherConnectionJob` を最外側commit後に投入する。失敗時はDBへ理由と次回時刻を保存し、5秒・30秒・2分・10分・以後30分間隔で再試行する。これは障害時の負荷調整であり、利用者の正常再接続の待機時間ではない。POSTの再確認と次回配信開始時には予定時刻を待たず同じ対象の切断を試せる。

キュー投入失敗・プロセス終了でも記録を失わない。`RetryPendingPublisherDisconnectsJob` が本番の既存Solid Queue定期実行で毎分、未解決かつ予定時刻を過ぎた行を拾う。重複投入は行ロックと切断の再実行性で許容する。外部通信中にDB保存が失敗した場合も、同じIDで再試行する。ジョブは終了・返却を再実行しない。

開始可否は、未解決の同じboothまたはuserの開始権を確認する。切断成功後にだけ解放し、条件を再判定して進む。無関係なbooth・userへ待機を設定しない。キャストの配信準備画面と管理可能なブース画面に切断待ちと「再確認」を表示する。管理画面は閉鎖済みも対象にでき、システムログには人物ID・店舗・セッション・connection ID・例外クラスを残す。トークン・メール・SDKの秘密をログへ出さない。

再確認は `POST /cast/booths/:id/retry_publisher_disconnect` と `POST /admin/booths/:id/retry_publisher_disconnect`。前者は本人connectionまたは当該ブースの操作権限、後者は管理権限を検証する。既に認可された切断意図だけを処理し、新しい強制終了の代用にしない。

## 6. D04：表示・コメント・集計・過去補正

### 6.1 表示と不明

セッションの配信者名・画像・プロフィールリンクはYを使う。Xを空欄時の代替にしない。準備は「配信未開始」、人物不明の履歴は「配信者不明」。記録済み退会者は既存の匿名化表示と公開範囲を維持する。不明にはプロフィールリンクを付けない。ブース自体の担当名・共有はZを維持し、配信セッションの共有・リザルトはYにする。

### 6.2 コメント（#1284で追加する保存契約）

通常コメントのuserは投稿者。配信者の強調・非表示権限は存在するYとの一致で判定し、独立した管理者権限を維持する。新規の消化通知はYを投稿者に保存する。

現行の公開側hide/unhideは準備作成者だけを許可するため、この本人判定をYへ変更する。管理画面の通報対応等の独立した管理者経路は維持し、公開側の本人専用APIへ一律に管理者権限を追加する変更は行わない。

不明の場合だけ `kind=drink_consumed`、`user_id=NULL`、metadataの `publisher_unknown=true` を許し「配信者不明」と表示する。comments.user_idの一律必須を、**userあり、または上記の不明消化通知に限る**DBチェック制約とモデル検証へ変更する。通常チャット・入退室・注文・その他system通知のNULLは拒否する。HTTPの通常コメント投稿はkind・user・不明フラグを利用者に指定させない。

`comments.drink_order_id` をNULL可の外部キーとして追加し、値ありに一意索引を付ける。新しい消化通知だけに注文IDを設定する。既存コメントを一括書換えせず、再試行時には既存の同注文の消化通知も確認して重複作成しない。売上・返却を再実行する回復にしない。

消化トランザクション内で通知コメントを重複なく保存し、表示通知は最外側commit後に送る。消化通知の保存は専用の処理で行い、通常コメントのlive/away・BAN・連投制御を変更しない。通知失敗は記録して同じcommentを再通知できるようにし、確定済み消化を失敗扱いに戻さない。未知の人物をX・Z・操作した管理者に代入しない。

### 6.3 集計（#1286）

`CastMetricsQuery` のセッション由来の人物キーをYへ変更する。消化台帳のpointsと既存の期間・配信時間の切詰め・率・丸めを維持する。対象ユーザーは現在担当に加え履歴のYを含め、配信した管理者・退会者の履歴も落とさない。

Yが不明な金額・時間はuser=NULLの「配信者不明」行へ集約し、既存のユーザー行の末尾に出す。NULLだから集計から除外しない。個人別行の消化ポイント合計と店舗台帳の同期間合計を照合する。個人別の既存計算・端数処理を変えて店舗精算額に一致させ直す変更は行わない。

### 6.4 旧履歴（#1287・#1289）

#1289は読み取りの対象一覧ファイルを作り、DB側の基準時刻・最大セッションID・対象ID・準備作成者・開始終了時刻・更新前値・一覧SHA-256を固定する。適用と中断再開は同じ一覧を必須とし、対象を再検索して増やさない。既存のバッチと同様に適用を明示し、実行時も行ロック下で対象条件・更新前値を再照合する。

対象は基準時点でstatus=endedかつended_atが整合し、broadcast_started_atあり、Yなし、現在ブースから参照されない旧セッションのみ。基準後に終了・新規作成・開始記録なし・設定済み・矛盾は除外する。Y=X、source=`legacy_creator_backfill`、recorded_at=適用時刻、evidenceに一覧参照と前後値を保存する。X、配信時刻、状態、台帳、既存コメントは変更しない。

#1287は資料の保存期間・Stage/IVSセッション/参加者属性とアプリセッションの対応を確認し、証拠なし・複数候補・矛盾を不明として残す。証拠補正はsource=`evidence_backfill`と根拠・前後値を保存し、確定済み値を無条件に上書きしない。既存の消化通知の人物補正も証拠で対象を限定し、通常コメントは変更しない。本番の適用は具体的な一覧を確認した判断を記録してから行う。

復旧は同じ対象一覧とevidenceの前後値を使い、適用後の値が保持されている行だけを元の新列値へ戻す。その後に別の証拠補正や新方式の記録がある行は上書きしない。稼働中・準備・新規行へ範囲を広げない。新たな汎用監査基盤・ユーザー置換・時刻推定は追加しない。

## 7. 呼び出し元と参照の変更一覧

| 呼び出し元／用途 | 変更・維持するもの | 担当・ケース |
| --- | --- | --- |
| StreamSessionのstarted_by関連、StartServiceの新規作成 | Xとして維持。actual関連・共通参照を追加 | #1282・#1299／P01〜P03 |
| StreamSessionPolicy#publish_token?の担当と最後の作成者参照 | 既存の所属・主担当・担当未設定時の認可を維持。本人配信判定には使わない | #1300／P04・P05 |
| StartService/StatusServiceのanother_live_booth_exists?、EnterAsCastServiceのlive判定 | 準備Xから実配信Yの共通参照へ | #1299・#1302／P03・P04・R01 |
| Cast::BoothsController#liveの本人復帰、publisherのauto resume | Yと現在要求を使用 | #1299・#1302／P04・R02 |
| Cast::BoothsControllerの選択候補優先・ApplicationHelperの切替確認 | ブース選択の業務仕様は #1255側。今回本人判定が必要な箇所だけ共通参照を使用し、選択方式を作り直さない | #1299／P04 |
| Token Controller→Ivs::CreateParticipantTokenService | viewer契約は維持。publisherは開始権Serviceへ。属性は認証actorから作る | #1300／S01・S02 |
| publisher Controller→api_client→start_broadcast→StatusService | published後の確定、要求識別、取消・再接続・終了を接続 | #1301〜#1303／S03〜S06・R01〜R03 |
| EndService/ForceEndServiceと管理者閉鎖・退会・所属解除 | D03へ統一。返却と実績を保持、切断再試行を分離 | #1303／E01〜E05 |
| CommentsControllerのhide/unhide、comment partialの強調 | 通常投稿者は維持、配信者本人はY、NULL同士は一致扱いしない | #1284／H02・H04 |
| ConsumeService→消化通知作成 | Y、または限定した不明通知。元の金銭確定は維持 | #1284／H02・H04 |
| BoothsControllerの@cast_user、stream_meta partial、リザルトの@cast_user | セッション由来はY、ブース担当表示はZのまま | #1285／H01・H04 |
| Cast::Booths::StreamSessionsControllerと履歴一覧 | Yの事前読込・名前・画像・リンク | #1285／H01 |
| BoothSharesHelperのstream_session_web_share_text | 配信共有はY。booth_web_share_textはZ | #1285／H01 |
| Admin::CommentReportsControllerと_cardのbroadcaster | 通報者・投稿者・対応者は維持し、配信者だけY | #1285／H01・H04 |
| HomeControllerのss/current_ss時刻・BoothCastの担当一覧／検索／お気に入り | 準備時刻による既存並び順と担当Zの用途を維持。人物記録追加で検索対象を変えない | #1285／H01 |
| CastMetricsQueryのユーザー候補・GROUP BY・時間加算 | Y、不明行。店舗金額・率・期間・丸めを維持 | #1286／H03・H04 |
| 旧履歴補完・証拠補正 | 限定した保存値の補完。実行時のX代替なし | #1287・#1289／M03・M04・H04 |

## 8. 27ケースの確認契約

各行は、操作前後のDB値、外部呼び出し対象、レスポンス・再試行を組にして検証する。テストデータはX/Y/Zを異なるユーザーにする。旧準備・旧履歴は新列がNULLの入力を使う。

| ID | 入力→操作 | 許可／拒否・保存前後・残る接続・画面と確認 |
| --- | --- | --- |
| P01 | 準備なし→Yが入場 | 許可。X=Yの準備1件、実配信者なし。情報閲覧では作らない。Service/導線テスト |
| P02 | Xの旧／新準備→Yが入場 | 許可。同じID・X・タイトル。新列NULLだけで拒否しない。旧準備を含むテスト |
| P03 | Aに準備のみ→YがBへ | 本人配信としない。Bの条件で許可。Aの値不変。別ブーステスト |
| P04 | AでY配信中→YがB／XがA | 拒否。AのYと接続を維持。外部トークンを発行しない |
| P05 | 閉鎖・終了・現在不一致・権限なし→直接要求 | 対象に拒否。別セッション・ブースを変更しない。各入口の認可テスト |
| S01 | 有効準備→発行 | 許可。connection所有者Yのみ。Y実績・初回時刻・liveは未保存 |
| S02 | X/Y同時開始、YのA/B同時開始 | 部分一意索引と世代で1件。負けた側は409。勝者の切断なし。別DB接続で競合テスト |
| S03 | SDK配信成功＋IVS一致→確定 | Y・初回時刻・live・connection確認を同時保存。X不変。SDK入力とServiceテスト |
| S04 | 発行前／参加失敗→取消・再利用 | 実績なし。同じ準備を保持し対象IDを切断。失敗はcancel_pending、成功後に再利用 |
| S05 | 外部参加後DB失敗／DB成功後応答消失 | 同じ要求の状態確認。未確定は取消、確定済みは同じYと時刻。重複実績なし |
| S06 | 外部照会失敗・矛盾・ページ途中失敗・世代変化 | 対象は確認不能。値・対象を保持し再確認。別の正常な対象は止めない |
| R01 | Y配信中→離席・復帰 | 許可。同じY・初回時刻・session。Xの要求は拒否 |
| R02 | 本人画面消失→新接続 | 旧IDの切断→新要求。同じYと時刻、固定待機なし。途中失敗は同じ対象で復帰 |
| R03 | 新接続後→古い開始／取消／状態／終了／ジョブ | 古い操作は現在を更新しない。旧IDへの再切断でも新IDは継続 |
| E01 | Xの未配信準備→権限Yが終了 | 許可。世代0・未発行も可。実績なし、準備終了。X違いだけで拒否しない |
| E02 | Y配信→通常／管理終了 | ended・offline・参照解除・返却1回。Yと初回時刻を履歴保持 |
| E03 | 旧／新準備→手動閉鎖 | 正規終了後に閉鎖。live/awayは先に終了を案内。未発行準備を閉じ込めない |
| E04 | 退会／所属解除→自動終了・閉鎖 | 既存対象と権限を保持。切断失敗でもDB成功なら後続完了。外側取消時の誤通知なし |
| E05 | 切断・DB・HTTP応答失敗→再試行 | 切断失敗は返却済み＋切断待ち。DB失敗は再試行。2重返却・新接続切断なし |
| M01 | 旧未配信準備→変更適用後に入場 | 同じ準備ID・Xで再利用。新列NULLの一律待機なし |
| M02 | 適用時に配信中なしという指定→導入 | 旧配信引継ぎ不要。旧準備保持。前提外の接続は根拠を示して判断へ戻す |
| M03 | 固定一覧の終了済み旧配信、開始あり、Yなし→補完 | Y=X、source=legacy_creator_backfill。一覧SHAと前後値を保持。時刻・台帳不変 |
| M04 | 未開始・基準後終了・新規・設定済み・不整合→補完 | 除外。再実行で対象を増やさず、別の記録を上書きしない |
| H01 | X/Y/Zが異なる→情報・履歴・共有・通報 | セッション配信者はY、担当はZ。リンク・画像・過去表示を確認 |
| H02 | X/Y/Zが異なる→コメント管理・消化 | 配信者本人はY。投稿者・管理者権限は維持。消化通知はY、通知失敗で再消化なし |
| H03 | X/Y/Zが異なる→個人別集計 | 消化金額・時間はY。不明行を含め店舗合計不変。未消化・返却を含めない |
| H04 | 未開始／不明／補完済み／退会済み→表示・通知・集計 | 文言・リンク・限定NULL通知・不明行・既存匿名化。Xへ暗黙補完しない |

## 9. 実装順序・有効化・運用

#1282で2節の保存領域・共通参照を追加。配信操作からの記録・制御への接続と、新方式の有効化は未実施。新列が空欄の既存データを維持する。

1. #1281：本書と関連仕様書・Issueを揃え、設計だけのPRを完了する。
2. #1282：保存領域と参照APIだけを追加。既存レコードの状態・人物を変更しない。
3. #1299→#1300→#1301→#1302→#1303：入口、発行、成功確定、再接続、終了・再試行を個別PRで実装する。原則1実装Issue=1PR。
4. #1284・#1285・#1286、#1287・#1289：コメント、表示、集計、旧履歴手順を個別PRで整備する。
5. #1288：27ケースと有効化を確認。実装途中は共通の `ACTUAL_PUBLISHER_CONTROL_ENABLED` がfalseの時に現行経路を使い、テストはtrueで新経路を確認する。全経路完成後に一括して有効化し、一部入口だけ新方式を利用者へ出さない。これはGit上の段階実装であり、記録専用の先行リリースや二段階デプロイを必須にするものではない。

有効化前に、配信中なしの指定前提、既存準備の保持、ジョブ稼働、実行環境のGetStage/ListParticipants/GetParticipant/DisconnectParticipant/CreateParticipantTokenの必要権限を確認する。検証用に追加したタグ限定権限はアプリ本体の全Stageの権限を意味しない。Terraformのステージング定義等へ必要な最小権限をコードで反映し、実環境の設定変更は対象を明示して扱う。

実配信者記録の有効化後に旧コードへ戻す場合、稼働中の新方式配信や切断待ちを残したまま旧経路を有効にしない。対象の状態と回復方法を確認してから切り戻す。今回の移行前提を、後の任意の切り戻しにも自動適用しない。履歴補完の適用範囲、未調査・未適用の実環境は結果を分けて報告する。
