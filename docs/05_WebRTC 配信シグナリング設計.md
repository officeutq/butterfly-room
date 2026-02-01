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

## 6. 注意点・制約（フェーズ1）

* 本番のスケールは IVS に委譲する（多数視聴を想定）
* 認可は必ず Rails で行い、token 発行をゲートにする
* Booth.status（live / away / offline）と映像UIは統合する

  * live：配信中（通常映像）またはスタンバイ（未配信）。実際の publish 状態はフロントが保持する
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
