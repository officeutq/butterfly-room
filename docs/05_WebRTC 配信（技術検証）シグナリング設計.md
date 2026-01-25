# WebRTC 配信（Phase1）シグナリング設計

本ドキュメントは、WebRTC 配信を **stream_session 単位**で管理するための  
ルーム構造・責務分離・シグナリング方式を定義する。

本設計はフェーズ1における **最小成立構成**であり、  
以降の配信関連 Issue はすべて本設計に従って実装する。

---

## 1. ルーム概念（stream_session 単位）

### ルームID
- `webrtc_room_id = stream_session.id`

### ルームの寿命
- `stream_session` の開始から終了まで
- booth に紐づく **current_stream_session のみ参加可能**

### 参加条件（概要）
- 対象の `stream_session` が存在し、かつ参加可能状態であること
- 詳細な認可条件（BAN / 所属確認など）は後続 Issue で実装する

---

## 2. ロール別責務（Phase1 固定）

### cast（配信者）
- **publisher**
- 映像・音声を送信する
- offer を生成する側

### customer / admin（視聴者・管理者）
- **viewer**
- 映像・音声を受信する
- offer を受信し、answer を返す側

※ Phase1 では viewer → publisher への昇格は行わない  
※ 複数 viewer を想定するが、P2P 構成のため規模は限定的とする

---

## 3. シグナリング方式

### 採用方式
- **ActionCable**
- JSON メッセージを中継するのみ（メディアは中継しない）

### チャンネル粒度
- stream_session 単位

  ```
  Channel: WebrtcRoomChannel
  Stream:  "webrtc_room:<stream_session_id>"
  ```

### 役割
- ActionCable は offer / answer / ice candidate を中継するのみ
- ビジネスロジックや状態管理は行わない

---

## 4. メッセージスキーマ（最低限）

### 共通フィールド
| key | 型 | 説明 |
|---|---|---|
| type | string | `"join" | "leave" | "offer" | "answer" | "ice"` |
| room_id | number | stream_session.id |
| from_user_id | number | 送信者 user_id |
| to_user_id | number / null | 宛先 user_id（P2P用） |

---

### join
視聴者がルームに参加したことを通知する

```json
{
  "type": "join",
  "room_id": 123,
  "from_user_id": 20
}
```

---

### leave

ルームから離脱したことを通知する

```json
{
  "type": "leave",
  "room_id": 123,
  "from_user_id": 20
}
```

---

### offer（publisher → viewer）

```json
{
  "type": "offer",
  "room_id": 123,
  "from_user_id": 10,
  "to_user_id": 20,
  "sdp": "..."
}
```

---

### answer（viewer → publisher）

```json
{
  "type": "answer",
  "room_id": 123,
  "from_user_id": 20,
  "to_user_id": 10,
  "sdp": "..."
}
```

---

### ice（相互）

```json
{
  "type": "ice",
  "room_id": 123,
  "from_user_id": 10,
  "to_user_id": 20,
  "candidate": {
    "candidate": "...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

### 補足：P2P（mesh）における相手決定ルール（技術検証）

- viewer は入室時に `join` をブロードキャストする（to_user_id 不要）
- publisher は `join` を受信したら、参加した viewer（= join の from_user_id）に対して `offer` を送る
  - `offer/answer/ice` は常に `to_user_id` を必須とし、1:1 の相手を明示する
- viewer は受信した `offer` の `from_user_id` を publisher とみなし、同一 user_id 宛に `answer/ice` を返す

---

## 5. 注意点・制約（技術検証）

* 本技術検証では P2P（mesh）構成を前提とする

  * viewer 数が増えると publisher 側の負荷が増大する
* ICE candidate は offer/answer より先に届く可能性がある

  * クライアント側でキュー処理が必要
* STUN / TURN サーバーは Phase2 以降で検討
* 認可（参加可否・BAN 等）は後続 Issue で段階的に実装する

---

## 6. 設計方針まとめ

* **ルーム単位：stream_session**
* **責務分離：cast = publisher / customer・admin = viewer**
* **シグナリング：ActionCable（JSON中継のみ）**
* **本設計を基準として以降の WebRTC Issue を実装する**
