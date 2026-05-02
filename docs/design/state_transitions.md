# State Transitions（現行実装確定版）

## 1. Booth 状態

```text
offline / standby / live / away
```

```mermaid
stateDiagram-v2
  [*] --> offline
  offline --> standby: StreamSessions::StartService
  standby --> live: StreamSessions::StatusService(to: live)
  live --> away: StreamSessions::StatusService(to: away)
  away --> live: StreamSessions::StatusService(to: live)
  live --> offline: StreamSessions::EndService
  away --> offline: StreamSessions::EndService
  standby --> offline: StreamSessions::EndService
```

補足:

- 配信開始直後、Booth は standby になる
- publisher は standby でも参加可能
- viewer は live / away のみ参加可能
- last_online_at は live / away 遷移時に更新される

---

## 2. StreamSession 状態

現行実装では、StreamSession は配信開始時に status: live で作成される。
終了時に status: ended になる。

```mermaid
stateDiagram-v2
  [*] --> live: StartServiceで作成
  live --> ended: EndService
```

補足:

- started_at はセッション作成時に記録
- ended_at は終了時に記録
- broadcast_started_at は実配信開始時刻として別途利用される
- 参加可否は StreamSession.status より Booth.status と current_stream_session_id を主に参照する

---

## 3. IVS参加状態

```mermaid
stateDiagram-v2
  [*] --> not_joinable
  not_joinable --> publisher_joinable: booth standby/live/away
  not_joinable --> viewer_joinable: booth live/away
  publisher_joinable --> not_joinable: booth offline or current_session不一致
  viewer_joinable --> not_joinable: booth offline/standby or current_session不一致
```

---

## 4. DrinkOrder 状態

```text
pending / consumed / refunded
```

```mermaid
stateDiagram-v2
  [*] --> pending: CreateService
  pending --> consumed: ConsumeService
  pending --> refunded: RefundService
  consumed --> [*]
  refunded --> [*]
```

確定ルール:

- 作成時は pending
- consumed になると売上確定
- refunded は pending のみ対象
- consumed 後の refund は現行実装では行わない
- 消化は FIFO 順

---

## 5. Wallet ポイント状態

```mermaid
stateDiagram-v2
  [*] --> available: purchase
  available --> reserved: hold
  reserved --> consumed: consume
  reserved --> available: release
```

実装上の意味:

- purchase: available_points 増加
- hold: available_points 減少、reserved_points 増加
- consume: reserved_points 減少
- release: reserved_points 減少、available_points 増加

WalletTransaction は履歴として以下を持つ。

```text
purchase / hold / release / consume / adjustment
```

---

## 6. StoreLedgerEntry

```mermaid
stateDiagram-v2
  [*] --> no_entry
  no_entry --> recorded: DrinkOrder consumed
  recorded --> [*]
```

- DrinkOrder consumed 時に作成
- 精算集計の根拠
- occurred_at が集計基準

---

## 7. Settlement 状態

```text
draft / confirmed / exported / paid
```

```mermaid
stateDiagram-v2
  [*] --> draft: monthly settlement
  [*] --> confirmed: manual settlement
  draft --> confirmed: 確定
  confirmed --> exported: SBI CSV出力
  exported --> paid: 支払完了
  confirmed --> paid: 手動支払完了
```

補足:

- monthly は draft で作成
- manual は confirmed で作成
- CSV出力対象は confirmed のみ
- CSV出力後は exported
- 店舗画面には confirmed / exported / paid のみ表示

---

## 8. SettlementCarryover

```mermaid
stateDiagram-v2
  [*] --> carried: 月次支払額が10,000円未満
  carried --> applied: 次回Settlementに加算
```

- 10,000円未満の場合、Settlementは作成しない
- 繰越は SettlementCarryover に記録する
- 次回支払可能時に相殺用のマイナス繰越を作成する
