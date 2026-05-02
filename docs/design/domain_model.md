# Domain Model（現行実装確定版）

## 1. コアドメイン

Butterflyve の主要ドメインは以下である。

- User / Membership
- Store / Booth
- StreamSession
- Comment
- Wallet / WalletTransaction
- DrinkItem / DrinkOrder
- StoreLedgerEntry
- Settlement / SettlementCarryover / SettlementExport

---

## 2. 全体構造

```text
User
 ├─ Wallet
 │   ├─ WalletPurchase
 │   └─ WalletTransaction
 │
Store
 ├─ StoreMembership
 ├─ Booth
 │   ├─ BoothCast
 │   └─ StreamSession
 │       ├─ Comment
 │       ├─ Presence
 │       └─ DrinkOrder
 │
 ├─ DrinkItem
 ├─ StoreLedgerEntry
 ├─ StorePayoutAccount
 ├─ Settlement
 ├─ SettlementCarryover
 └─ SettlementExport
```

---

## 3. User / Membership

User.role はアプリ全体の権限を表す。
StoreMembership は店舗内の所属・権限を表す。

- customer: 視聴者
- cast: キャスト
- store_admin: 店舗管理者
- system_admin: システム管理者

---

## 4. Store / Booth

Store は店舗単位であり、Booth は配信単位である。

Booth は以下の状態を持つ。

```text
offline / standby / live / away
```

Booth は IVS Stage ARN を保持する。
StreamSession は配信開始時に Booth の Stage ARN をコピーして保持する。

---

## 5. StreamSession

StreamSession は配信セッションを表す。

主な属性:

- started_at
- broadcast_started_at
- ended_at
- status
- ivs_stage_arn
- started_by_cast_user_id

現行実装では、配信開始時に StreamSession.status は live として作成されるが、視聴可否や参加可否は Booth.status と current_stream_session_id を主に参照する。

---

## 6. Wallet

Wallet は視聴者ごとのポイント残高を保持する。

- available_points: 利用可能ポイント
- reserved_points: ドリンク注文で仮押さえ中のポイント

WalletTransaction は残高変動履歴である。

```text
purchase / hold / release / consume / adjustment
```

---

## 7. Drink

DrinkItem は店舗が販売するドリンクメニューである。
DrinkOrder は視聴者のドリンク注文である。

状態:

```text
pending / consumed / refunded
```

重要ルール:

- 作成時は pending
- 消化時に consumed
- 配信終了時に残 pending は refunded
- consumed 後の refunded は現行実装では行わない
- 消化は StreamSession 内の FIFO 順で行う

---

## 8. StoreLedgerEntry

StoreLedgerEntry は店舗売上台帳である。
DrinkOrder が consumed になった時点で作成される。

- 1 DrinkOrder に対して1 StoreLedgerEntry
- points は売上ポイント
- occurred_at は売上計上日時
- 精算集計の基準日時になる

---

## 9. Settlement

Settlement は店舗への支払単位である。

状態:

```text
draft / confirmed / exported / paid
```

月次精算では、StoreLedgerEntry を店舗・期間ごとに集計する。
店舗取り分は70%である。

10,000円未満の場合は Settlement を作らず、SettlementCarryover に繰り越す。

CSV出力時、Settlement は exported になり、振込先口座情報がスナップショット保存される。

---

## 10. ドメイン上の確定ルール

- 売上確定は DrinkOrder.consumed 時
- 売上集計は StoreLedgerEntry.occurred_at 基準
- 未消化ドリンクは配信終了時に返金
- ドリンク消化は FIFO
- Stage は Booth 固定
- StreamSession は Booth の Stage ARN をコピー保持
- 月次精算の店舗取り分は70%
- 月次精算の最低支払額は10,000円
