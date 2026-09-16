# 配信設計（Phase1 / 本番：Amazon IVS Real-Time）

2026-09-16ローカル追加：非公開店舗は全役割で準備・開始不可。準備画面から非公開店舗のブースへ選択を変えた場合は、準備を作らず管理用情報で理由を案内する。通常の店舗編集による非公開化は、店舗内の配信中・離席中・開始処理中を確認して拒否する。競合時の店舗ロックと終了・取消の維持は[実配信者設計1.1節](design/actual_publisher.md)を参照。

ブース・店舗の選択は#1255の[共通契約](design/current_selection.md)に従い、#1274〜#1276でローカル実装済み（ステージング・本番へ未反映）。選択側は#1280で実装済みのDB参照を利用し、準備作成者・未確定の開始権を本人配信と読み替えない。選択だけで準備・配信開始・終了を行わず、明示的な準備画面への移動で既存Serviceを呼ぶ。他者配信中や閉鎖済みは選択できても準備・開始できない。新方式の配信成功確定・世代・切断再試行の契約は維持する。

本ドキュメントは、配信機能を **stream_session 単位**で成立させるための
ルーム構造・責務分離・本番配信方式・制御（シグナリング）・最低限のメッセージ形式を定義する。

フェーズ1リリースの本番配信方式は **Amazon IVS Real-Time Streaming** とする。
以降の配信関連 Issue は本設計に従って実装する。

---

## 1. ルーム概念（stream_session 単位）

### ルームID
配信ルームの論理IDは以下とする。

- `room_id = stream_session.id`

### ルームの寿命
- `stream_session` の開始から終了まで
- booth に紐づく **current_stream_session のみ参加可能**

### 参加条件（概要）
- 対象 `stream_session` が存在し、参加可能状態であること（live / away）
- 認可（BAN / 所属確認など）は Rails 側で制御する（詳細は後続 Issue）

---

## 2. ロール別責務（固定）

### 配信権限を持ち、配信として入った人
- **publisher**
- 映像・音声を publish する責務を持つ
- 配信開始 / 終了の主体

### 視聴として入った人（未ログイン / customer / cast / admin）
- **viewer**
- 映像・音声を subscribe する責務を持つ
- 配信開始 / 終了を制御しない
- 未ログインは公開店舗のlive / awayだけを購読でき、在室・視聴者数には含めない

※ Phase1 では viewer → publisher の昇格は行わない  
※ viewer は複数を許容する（本番はIVSによりスケールさせる）

---

## 3. 本番配信方式（フェーズ1リリース）

### 採用方式
- **Amazon IVS Real-Time Streaming**
- アプリ（Rails）は映像を中継しない（配信基盤が中継する）

### 対応関係（ルーム ↔ IVS）
- IVS Stageは **boothに固定**する。各 `stream_session` はそのARNをコピーして保持し、同じブースの後続セッションでも同じStageを使う
- 以降、この Stage を「配信ルームの実体」として扱う
- IVSの `activeSessionId` とアプリの `stream_session.id` は別の識別子。前者は参加者照会に、後者は業務・認可・履歴に使う

---

## 4. シグナリング（配信制御）方式

### 目的
publisher / viewer が同一の配信ルーム（stream_session / IVS Stage）に参加し、
配信開始・視聴・終了を成立させるための「参加制御」を定義する。

### 本番のシグナリング方式
- **Rails が Participant Token を発行する**
- フロントは **IVS SDK で Stage に join** する
- join / leave / publish などのイベントは **IVS SDK のイベント**として取り扱う

### Rails 側の責務
- 認可（booth所属・BAN・role）
- token 発行（publisher / viewer の権限分離）
- stream_session と IVS Stage の対応管理
- Booth.status と配信UIの整合

### 追加：配信UI状態（Phase1 Improve 方針）

Phase1 の UI は「セッション（Rails）」と「実配信（IVS publish）」を分離し、
**スタンバイ中は viewer に何も配信しない**ことを明確にする。

- **サマリー**：stream_session なし（または終了済み）
- **スタンバイ**：stream_session あり / cast はプレビュー可能 / **publish は開始しない**
- **配信中**：publish 中（映像＋音声）
- **席外し中**：publish 継続。ただし映像は「席外し中」画面に差し替え、音声は既定でミュート

> 重要：viewer が見られるか（joinable）は Rails 状態で判定するが、
> 「スタンバイ中は未配信」を保証するため、cast は Stage join / publish を開始しない。

#### ボタン（3つ、トグル）
- **スタンバイ ⇔ サマリー**：stream_session の作成/終了（finish）
- **配信開始 ⇔ 配信終了**：IVS publish の開始/停止。終了結果を確認して配信リザルトへ進む。新経路では外部切断待ちでもDB終了・返却が確定すれば結果と再確認を案内する
- **席外し ⇔ 復帰**：配信中のみ。映像を「席外し中」画面へ切替/復帰


---

## 5. メッセージ形式（最低限）

本番方式（IVS）における「配信制御メッセージ」は以下とする。

### 5.1 Token 発行リクエスト（Rails API）
フロントは、参加前に token を取得する。

#### Request（例）
```json
{
  "room_id": 123,
  "role": "publisher"
}
```

* `room_id`: stream_session.id
* `role`: `"publisher"` or `"viewer"`

#### Response（例）

```json
{
  "room_id": 123,
  "ivs_stage_arn": "arn:aws:ivs:...",
  "participant_token": "..."
}
```

### 5.2 参加イベント（IVS SDK 側）

IVS SDK のイベントとして、最低限以下の概念を扱う。

| type            | 意味                     | 発生源 |
| --------------- | ---------------------- | --- |
| join            | 参加（Stage join）         | SDK |
| leave           | 離脱                     | SDK |
| publish_started | publisher が publish 開始（映像/音声トラック送出開始） | SDK |
| publish_stopped | publisher が publish 停止（送出停止） | SDK |

※ 実際のイベント名は SDK に従う（本設計では「扱うべき概念」を固定する）

---

## 6.参加トークン発行API（Participant Token API）仕様（role分岐・スタンバイ封じ）

### 目的

* **配信事故防止**のため、**viewer 起点で Stage を作成しない**ことを保証する
* **スタンバイ中は viewer が join できない**ことを API レベルで担保する（UI が残っていても安全）
* publisher は **スタンバイ中でも準備を進められる**（token取得は許可）


### 用語と状態

* #### Booth.status（サーバ側の配信状態）

  * `offline`：配信セッションなし
  * `standby`：配信セッション作成済み（準備中）だが、視聴者には見せない
  * `live`：配信中
  * `away`：席外し中（視聴は継続するが、映像は切り替える想定）

  ※ `standby` は既存 enum の末尾追加で導入する（既存値を壊さない）。

### join 可能条件（最重要ルール）

参加（token発行・join）の可否は **role（viewer/publisher）ごと**に判定する。

* #### 共通条件

  * `booth.current_stream_session_id == stream_session.id` が一致していること
    → “今の配信セッション” と一致しない限り join 不可（409 not_joinable）

* #### viewer の join 条件（厳格）

  * `booth.status` が `live` または `away` のときのみ join 可能
  * `standby` は **join 不可**
  * `stream_session.ivs_stage_arn` が空の場合は **409 stage_not_bound**
  * 未ログインは公開店舗のactive boothに紐づくstream_sessionに限り、`SUBSCRIBE` capabilityだけを持つtokenを取得可能
  * 未ログインtokenのattributesには `user_id` を含めず、発行APIにはsession単位のrate limit（発行頻度制限）を適用する
  * BAN対象customerは従来どおり **403 forbidden** とする

    * viewer 側のトリガで Stage を生成させない（事故防止）
    * viewer role では Stage ensure（作成）を **行わない**

* #### publisher の join 条件（準備を許可）

  * `booth.status` が `standby` / `live` / `away` のいずれかなら join 可能（ただし current_session 一致は必須）
  * `stream_session.ivs_stage_arn` が空の場合は **409 stage_not_bound** とする。トークン要求からStageを作成しない
  * Stageの作成は配信側のブース作成・準備に属する `Booths::ProvisionIvsStageService` の責務とする

### Token API のレスポンス／エラー

* #### 正常（200）

  * `stream_session_id`
  * `ivs_stage_arn`
  * `role`
  * `participant_token`

* #### エラー（主にUI制御・事故防止目的）

  * 404 `not_found`：stream_session が存在しない
  * 422 `missing_role`：role パラメータがない
  * 422 `invalid_role`：role が viewer/publisher 以外
  * 409 `not_joinable`：join 条件を満たさない（current_session 不一致、viewer が standby など）
  * 409 `stage_not_bound`：viewer で Stage 未準備（ivs_stage_arn 空）
  * 403 `forbidden`：権限不足（サービス側の認可）
  * 429 `rate_limited`：未ログインviewerの発行頻度超過

### Stage作成の責務分離

* Stageは `Booths::ProvisionIvsStageService` がboothへ一度紐づける。旧 `EnsureIvsStageService` によるセッション単位の作成方式は使用しない
* viewerのアクセス、トークン発行、配信の再接続でStageを新規作成しない
* ARNがない場合はviewer/publisherとも `stage_not_bound`。既存Stageを通常の復旧で削除・作り直ししない

### スタンバイ開始（StreamSessions::StartService）の仕様

* #### 目的

  * “配信準備中（スタンバイ）” をサーバ状態として確定させ、viewer を封じる
  * この時点ではStageを作成せず、既にboothへ紐づいたARNを配信セッションへコピーする

* #### 処理

  * `booth.offline?` を前提に、新しい `stream_session` を作成
  * Booth を `standby` にし、`current_stream_session_id` を新しいセッションに紐付ける
  * `EnsureIvsStageService` は **呼ばない**


* #### スタンバイ中の配信メタ情報入力

  * スタンバイ開始時に `stream_sessions` を `status=live` で作成し、`booth.current_stream_session_id` に紐付ける。これにより、スタンバイ中に配信タイトル（`stream_sessions.title`）を編集可能とする。standbyは `Booth.status` だけが保持する。
  * 編集は **current_session**一致かつ **booth.status=standby** の場合に限定し、配信中（live/away）は原則 read-only とする（事故防止）。
  * 視聴側の表示は `stream_session.title` を優先し、未入力の場合は `booth.name` をフォールバック表示する。



* #### 結果

  * “スタンバイ中” は **セッションは存在する**が、viewer join は不可能（APIとUIで二重に封じる）

### Public（viewer）画面の表示制御

* #### 目的

  * スタンバイ中に「黒画面」「繋がりそうなUI」を出さない
  * ただし UI が残っても Token API が最後の砦として join を拒否する

* #### 仕様

  * `@stream_session` が存在し、かつ `booth.status` が `live` / `away` の場合のみ視聴UI（ivs_viewer）を表示する
  * `@stream_session` が存在するが `booth.status` が `standby` の場合は、

    * 視聴UIを表示しない
    * 代わりに「配信準備中（スタンバイ）」を表示する

### 設計上の狙い（まとめ）

  * スタンバイ中は **UIでもAPIでも** viewer を join させない（二重防御）
  * Stage 作成は publisher 起点に限定し、**viewer による stage 増殖事故**を構造的に防ぐ
  * `booth.current_stream_session_id` を “正” として join 可否を判断し、**セッション整合性**を担保する

---

## 6. 注意点・制約（フェーズ1）

* 本番のスケールは IVS に委譲する（多数視聴を想定）
* 認可は必ず Rails で行い、token 発行をゲートにする
* Booth.status（live / away / offline / standby）と映像UIは統合する

  * live：配信中（通常映像）。実際の publish 状態はフロントが保持する
  * away：配信継続。映像は「席外し中」画面へ切替（publisher/viewer とも同一映像）
  * offline：配信終了（Rails finish）。viewer 側は joinable=false を検知して終了状態へ

### 音声の扱い（席外し中）

席外し中は事故防止のため **既定でミュート** とし、UI で切り替え可能にする。

- 既定：away へ遷移した時点で publisher の audio track を `enabled=false`（ミュート）
- 切替：cast UI で「席外し中も音声を流す」を ON にできる（ただし既定は OFF）
- 復帰：live へ戻るときは audio を既定で ON（または直前設定を維持。実装で統一する）

> Phase1 では「ページ再読み込みで復帰」を許容するため、音声設定は永続化せずフロント状態でよい。

---

## 7. 設計方針まとめ

* **ルーム単位：stream_session**
* **責務分離：配信として入る権限者 = publisher / 視聴として入る人 = viewer**
* **本番配信方式：Amazon IVS Real-Time（Stage + Token + SDK join）**
* **シグナリング方式：Rails による token 発行 + IVS SDK イベント**
* **以降の配信関連 Issue は本設計を前提として実装する**

## 8. 実配信者と接続管理（#1280の目標仕様）

保存列・API・27ケースは [実配信者設計](design/actual_publisher.md)、採用した外部契約は [実測資料](design/legacy_publisher_migration_research.md) を参照する。以下の契約は実装済みで、2026-09-15にstaging・本番で有効化した。環境ごとの実施内容・未実施の確認は [適用記録](ops/actual_publisher_rollout.md) を参照する。

- publisherの発行要求は `request_id` と `expected_generation` を追加し、開始権を1件だけ確保する。参加者ID・期限・人物・対象をDBへ保存してからトークンを返す。発行だけでは実配信者・開始時刻・booth.liveを設定しない。
- 自分のSDKの `published` イベント後に、`request_id` と `generation` を既存の開始確定APIへ送る。GetStage→ListParticipants全ページ→GetParticipant→GetStageで参加者属性・状態・対象を照合し、実配信者・初回時刻・liveを同じDBトランザクションで保存する。
- `ListParticipants` はstage_arnとIVSのsession_idが必須。属性は要約でなくGetParticipantで読む。`DisconnectParticipant` はstage_arnとparticipant_idを指定し、stage_session_idを渡さない。
- 通常leave・自然切断・トークン期限は、保存した参加権限の失効の証拠にしない。取消・再接続・終了は保存した参加者IDへ切断を要求する。未参加でも切断は可能。同じIDへの再切断は、新しいIDへ影響しない。
- 配信成功のDB保存後に応答が消失しても、同じ要求の確認で同じ人物・初回時刻を返す。別タブや遅い要求を最新接続へ割り当てない。通常の再接続に固定待機を追加しない。
- 終了・返却はIVS切断失敗時もDBへ確定し、外部切断だけを記録して再試行する。閉鎖・退会後も記録を保持する。同じブース・人物の次回開始は切断待ちを再確認してから許可する。
- viewerのSUBSCRIBE専用・standby参加禁止・公開範囲・BAN条件は維持する。全画面で常時IVSへ問い合わせる方式にはしない。
