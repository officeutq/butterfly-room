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
| publish_started | publisher が publish 開始 | SDK |
| publish_stopped | publisher が publish 停止 | SDK |

※ 実際のイベント名は SDK に従う（本設計では「扱うべき概念」を固定する）

---

## 6. 注意点・制約（フェーズ1）

* 本番のスケールは IVS に委譲する（多数視聴を想定）
* 認可は必ず Rails で行い、token 発行をゲートにする
* Booth.status（live / away / offline）と映像UIは統合する

  * live：映像表示
  * away：映像 + オーバーレイ
  * offline：映像停止 + 終了カード

---

## 7. 設計方針まとめ

* **ルーム単位：stream_session**
* **責務分離：cast = publisher / customer・admin = viewer**
* **本番配信方式：Amazon IVS Real-Time（Stage + Token + SDK join）**
* **シグナリング方式：Rails による token 発行 + IVS SDK イベント**
* **以降の配信関連 Issue は本設計を前提として実装する**
