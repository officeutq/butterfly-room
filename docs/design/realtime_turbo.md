# Realtime UI / Turbo Streams 設計

## 1. 概要

本アプリは、ライブ配信中のコメント、ドリンク、ウォレット残高、配信状態をリアルタイムに近い形で更新する。
主な仕組みは Turbo Streams Channel と Stimulus Controller の組み合わせである。

---

## 2. Turbo Stream 更新対象

### 2.1 コメント

CommentNotifier がコメントを配信する。

```text
broadcast_append_to [stream_session, :comments]
target: comments
partial: comments/comment
```

コメント編集・非表示時は replace を使う。

```text
broadcast_replace_to [stream_session, :comments]
target: comment_x
partial: comments/comment
```

---

### 2.2 ドリンク未消化一覧

DrinkOrderNotifier が未消化ドリンク一覧を更新する。

視聴者/公開側:

```text
[stream_session, :pending_drink_orders]
target: pending_drink_orders
partial: stream_sessions/pending_drink_orders
```

キャスト側:

```text
[stream_session, :cast_pending_drink_orders]
target: cast_pending_drink_orders
partial: cast/stream_sessions/pending_drink_orders
```

---

### 2.3 ウォレット残高

WalletNotifier がユーザー単位で残高を更新する。

```text
[user, :wallet]
target: wallet_balance
partial: wallets/balance
```

---

### 2.4 配信状態

StreamSessionNotifier が配信状態やメタ情報を更新する想定。

主な用途:

- 視聴ページの live / waiting 切替
- 配信終了表示
- 配信メタ情報更新

---

## 3. コメント欄UX

comment_panel_controller がコメントリストを監視する。

仕様:

- 初期表示時に最下部へスクロール
- ユーザーが下端付近にいる場合のみ、新着コメントで自動スクロール
- ユーザーが過去コメントを読んでいる時は勝手に最下部へ移動しない

---

## 4. 視聴ページ状態同期

viewer_page_controller は `#stream_state [data-live-like]` を監視する。

live-like が true:

- liveRoot を表示
- waitingRoot を非表示
- お気に入りボタンをライブ用配置に移動

live-like が false:

- liveRoot を非表示
- waitingRoot を表示
- お気に入りボタンを待機画面側配置に戻す

---

## 5. 視聴者数

presence_poll_controller により、定期的に視聴者数を更新する設計である。

用途:

- 視聴ページの現在人数表示
- キャスト側の配信中メタ情報表示

---

## 6. リアルタイム更新の責務分担

```text
Model / Service
  ↓
Notifier
  ↓
Turbo Streams Channel
  ↓
View partial
  ↓
Stimulus Controller
```

### Rails側

- 何が起きたかを判断する
- DB更新後に必要なTurbo Streamを配信する

### View側

- 更新対象DOMを持つ
- partialとして再描画可能にする

### Stimulus側

- 再描画後のUI状態を整える
- スクロールや開閉状態を制御する

---

## 7. 設計上の注意点

- Turbo Stream の target id は設計上の契約になる
- partialのDOM構造を変える場合はStimulus側のselectorも確認する
- コメントやドリンク一覧は配信中に高頻度更新されるため、partialを重くしすぎない
- Turbo cache前に外部SDKやPopoverをcleanupする必要がある
