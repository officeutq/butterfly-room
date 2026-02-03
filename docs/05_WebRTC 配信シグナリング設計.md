# 配信設計（Phase1 / 本番：Amazon IVS Real-Time）

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

### cast（配信者）
- **publisher**
- 映像・音声を publish する責務を持つ
- 配信開始 / 終了の主体

### customer / admin（視聴者・管理者）
- **viewer**
- 映像・音声を subscribe する責務を持つ
- 配信開始 / 終了を制御しない

※ Phase1 では viewer → publisher の昇格は行わない  
※ viewer は複数を許容する（本番はIVSによりスケールさせる）

---

## 3. 本番配信方式（フェーズ1リリース）

### 採用方式
- **Amazon IVS Real-Time Streaming**
- アプリ（Rails）は映像を中継しない（配信基盤が中継する）

### 対応関係（ルーム ↔ IVS）
- `stream_session` は 1 つの **IVS Stage** に対応する（1:1）
- 以降、この Stage を「配信ルームの実体」として扱う

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
- **配信開始 ⇔ 配信終了**：IVS publish の開始/停止。終了時は即サマリーへ戻す
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

    * viewer 側のトリガで Stage を生成させない（事故防止）
    * viewer role では Stage ensure（作成）を **行わない**

* #### publisher の join 条件（準備を許可）

  * `booth.status` が `standby` / `live` / `away` のいずれかなら join 可能（ただし current_session 一致は必須）
  * `stream_session.ivs_stage_arn` が空の場合は **publisher role のみ** Stage ensure を実行してから token を発行する
    → Stage の作成責務は publisher 側に限定する

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

### Stage 作成（EnsureIvsStageService）の責務分離

* **Stage 作成（ensure）は publisher 起点のみ**で許可する

  * viewer 起点では実行しない（万一 UI/JS が誤って呼んでも Stage が増えない）
* `stream_session.ivs_stage_arn` が空の場合：

  * viewer：409 `stage_not_bound`
  * publisher：`EnsureIvsStageService` を実行してから token 発行

### スタンバイ開始（StreamSessions::StartService）の仕様

* #### 目的

  * “配信準備中（スタンバイ）” をサーバ状態として確定させ、viewer を封じる
  * Stage は **この時点では作成しない**（配信開始＝publisher join のタイミングで初めて作成）

* #### 処理

  * `booth.offline?` を前提に、新しい `stream_session` を作成
  * Booth を `standby` にし、`current_stream_session_id` を新しいセッションに紐付ける
  * `EnsureIvsStageService` は **呼ばない**


* #### スタンバイ中の配信メタ情報入力

  * スタンバイ開始時に `stream_sessions` を作成し、`booth.current_stream_session_id` に紐付ける。これにより、スタンバイ中に配信タイトル/説明（`stream_sessions.title / stream_sessions.description`）を編集可能とする。
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
* **責務分離：cast = publisher / customer・admin = viewer**
* **本番配信方式：Amazon IVS Real-Time（Stage + Token + SDK join）**
* **シグナリング方式：Rails による token 発行 + IVS SDK イベント**
* **以降の配信関連 Issue は本設計を前提として実装する**
