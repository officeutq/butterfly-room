# State Transitions（状態遷移設計）

## 1. 概要

本ドキュメントは、Butterflyve の主要な状態遷移を整理する。

対象は以下とする。

* Booth
* StreamSession
* DrinkOrder
* WalletTransaction
* Settlement

---

## 2. Booth 状態

### 2.1 状態一覧

```text
offline / standby / live / away
```

### 2.2 状態遷移

```mermaid
stateDiagram-v2
  [*] --> offline
  offline --> standby: 配信準備開始
  standby --> live: 映像配信開始
  live --> away: 一時離席
  away --> live: 配信復帰
  live --> offline: 配信終了
  standby --> offline: 配信中止
  away --> offline: 配信終了
```

### 2.3 補足

* Booth は視聴者向け表示状態として扱う
* 実際の配信セッションは StreamSession が保持する
* Booth.status と StreamSession.status の同期ルールは明文化が必要

---

## 3. StreamSession 状態

### 3.1 主な日時

```text
started_at
broadcast_started_at
ended_at
```

### 3.2 状態遷移

```mermaid
stateDiagram-v2
  [*] --> started: セッション作成
  started --> broadcasting: broadcast_started_at 記録
  broadcasting --> away: 一時離席
  away --> broadcasting: 復帰
  broadcasting --> ended: ended_at 記録
  away --> ended: ended_at 記録
  started --> ended: 配信中止
```

### 3.3 補足

* started_at は配信枠開始を表す
* broadcast_started_at は実際の映像配信開始を表す
* ended_at が入った時点で終了済みとみなす

---

## 4. DrinkOrder 状態

### 4.1 状態一覧

```text
pending / consumed / refunded
```

### 4.2 状態遷移

```mermaid
stateDiagram-v2
  [*] --> pending: ドリンク送信
  pending --> consumed: 消化
  pending --> refunded: 返金
  consumed --> [*]
  refunded --> [*]
```

### 4.3 ドメインルール

* pending は注文作成済み・未消化状態
* consumed になった時点で店舗売上が確定する
* refunded は返金済み状態
* consumed 後の refunded 可否は要確認

---

## 5. WalletTransaction 種別

### 5.1 種別一覧

```text
purchase / hold / release / consume / adjustment
```

### 5.2 ポイント処理フロー

```mermaid
stateDiagram-v2
  [*] --> purchase: ポイント購入
  purchase --> available: 残高反映

  available --> hold: ドリンク送信
  hold --> consume: ドリンク消化
  hold --> release: キャンセル/返金

  consume --> [*]
  release --> available
  available --> adjustment: 管理調整
  adjustment --> available
```

### 5.3 補足

* WalletTransaction は状態そのものではなく、残高変動履歴
* Wallet.balance と必ず整合する必要がある
* DrinkOrder と同一トランザクションで処理する必要がある

---

## 6. StoreLedgerEntry 状態

### 6.1 位置づけ

StoreLedgerEntry は状態遷移よりも、売上確定イベントとして扱う。

```mermaid
stateDiagram-v2
  [*] --> no_entry: 未計上
  no_entry --> recorded: DrinkOrder consumed
  recorded --> [*]
```

### 6.2 ドメインルール

* DrinkOrder が consumed になった時点で作成される
* 店舗売上の根拠となる
* Settlement の集計対象になる

---

## 7. Settlement 状態

### 7.1 状態一覧

```text
draft / confirmed / exported / paid
```

### 7.2 状態遷移

```mermaid
stateDiagram-v2
  [*] --> draft: 精算作成
  draft --> confirmed: 精算確定
  confirmed --> exported: 振込CSV出力
  exported --> paid: 支払完了
  confirmed --> paid: CSVを使わず支払完了
```

### 7.3 ドメインルール

* draft は仮作成状態
* confirmed 以降は金額・振込先情報を固定する
* exported は振込データ出力済み状態
* paid は支払完了状態
* 精算期間は重複不可

---

## 8. 店舗振込先状態

### 8.1 状態

```text
active / inactive
```

### 8.2 状態遷移

```mermaid
stateDiagram-v2
  [*] --> active: 登録
  active --> inactive: 無効化
  inactive --> active: 再有効化
```

### 8.3 ルール

* 店舗ごとに active な振込先は1件のみ
* 精算確定時点で振込先情報を Settlement にスナップショット保存する

---

## 9. 要確認事項

以下はコードだけでは仕様確定しきれないため、別途確認する。

* Booth.status と StreamSession.status の正本
* consumed 後の refunded を許可するか
* 配信中の away 状態の扱い
* 強制終了時の DrinkOrder pending の扱い
* 精算 confirmed 後の修正可否
* paid 後の取消・再精算可否

---
