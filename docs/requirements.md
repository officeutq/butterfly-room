# Butterflyve 要件定義書（現行実装確定版）

## 1. 概要

Butterflyve は、視聴者・キャスト・店舗をつなぐライブ配信サービスである。
視聴者は配信を視聴し、コメントおよびドリンク送信によりキャストを応援できる。
ドリンクはポイントを仮押さえして送信され、消化時に店舗売上として確定する。

---

## 2. ユーザー種別

本システムは以下のユーザー種別を持つ。

- customer
- cast
- store_admin
- system_admin

店舗との所属関係は StoreMembership により管理する。

---

## 3. 認証・アクセス制御

- 原則として全ページでログインを必須とする
- 未ログイン時は Devise により認証へ誘導する
- ログイン後は stored_location があればそこへ戻る
- ユーザーが所属する店舗・ブースが1件のみの場合、ログイン時に current_store / current_booth を自動選択する

---

## 4. 店舗・ブース

### 4.1 店舗

店舗は以下を持つ。

- ブース
- ドリンクメニュー
- 店舗メンバー
- 振込先口座
- 精算情報

### 4.2 ブース

ブースは配信の表示単位であり、以下の状態を持つ。

```text
offline / standby / live / away
```

Phase1では、1ブースに対して主担当キャスト1名を基本とする。

---

## 5. 配信機能

### 5.1 配信開始

配信開始時、以下を行う。

- 対象ブースをロックする
- ブースが offline であることを確認する
- ブースが archive されていないことを確認する
- 他のブースで同一キャストが live / away でないことを確認する
- booth.ivs_stage_arn が存在することを確認する
- StreamSession を作成する
- Booth.status を standby にする
- Booth.current_stream_session_id を設定する

### 5.2 IVS Stage

- Stage は Booth に固定で紐づく
- StreamSession 作成時に booth.ivs_stage_arn をコピーする
- Token発行リクエストをトリガーにStageを作成しない

### 5.3 参加条件

Publisher:
- booth.status が standby / live / away
- current_stream_session_id が一致
- 権限を持つ cast / store_admin / system_admin

Viewer:
- booth.status が live / away
- current_stream_session_id が一致
- 権限を持つユーザー

### 5.4 配信終了

配信終了時、以下を行う。

- Booth.status を offline にする
- Booth.current_stream_session_id を nil にする
- pending の DrinkOrder を refund する
- StreamSession.ended_at を記録する
- StreamSession.status を ended にする

---

## 6. コメント機能

コメントは StreamSession に紐づく。
主な種別は以下。

```text
chat / drink / drink_consumed / entry / exit / system
```

ドリンク送信時には drink コメント、ドリンク消化時には drink_consumed コメントを作成する。

---

## 7. ポイント・ウォレット

### 7.1 ポイント購入

固定プランで購入する。

```text
1,000pt   = 1,100円
5,000pt   = 5,500円
10,000pt  = 11,000円
50,000pt  = 55,000円
100,000pt = 110,000円
```

Stripe Checkout で決済し、Webhook等で購入反映時に Wallet.available_points を増加させる。

### 7.2 ウォレット

Wallet は以下を持つ。

- available_points
- reserved_points

### 7.3 取引種別

```text
purchase / hold / release / consume / adjustment
```

---

## 8. ドリンク注文

### 8.1 作成条件

ドリンク注文は以下の場合のみ可能。

- Booth.status が live または away
- DrinkItem が同じ店舗に属する
- DrinkItem が enabled
- price_points が正の値
- Wallet.available_points が価格以上

### 8.2 作成時処理

ドリンク送信時、同一トランザクションで以下を行う。

- Wallet.available_points を減らす
- Wallet.reserved_points を増やす
- DrinkOrder を pending で作成する
- WalletTransaction(kind: hold, points: -price) を作成する
- Comment(kind: drink) を作成する

### 8.3 消化処理

ドリンク消化時、以下を行う。

- 対象 DrinkOrder が pending であることを確認する
- 同一 StreamSession 内の pending 先頭であることを確認する（FIFO）
- hold transaction が1件だけ存在することを確認する
- Wallet.reserved_points を減らす
- WalletTransaction(kind: consume, points: price) を作成する
- DrinkOrder.status を consumed にする
- consumed_at を記録する
- StoreLedgerEntry を作成する
- Comment(kind: drink_consumed) を作成する

### 8.4 返金処理

配信終了時、残っている pending 注文のみ refunded にする。

- pending DrinkOrder をロックする
- 対応する hold transaction を確認する
- Wallet.reserved_points を減らす
- Wallet.available_points を戻す
- WalletTransaction(kind: release, points: price) を作成する
- DrinkOrder.status を refunded にする
- refunded_at を記録する

consumed 後の refunded は現行実装上は対象外。

---

## 9. 店舗売上

StoreLedgerEntry は、DrinkOrder が consumed になった時点で作成される。
売上集計は StoreLedgerEntry.occurred_at を基準とする。
1pt = 1円として扱う。

---

## 10. 精算

### 10.1 精算種別

- manual
- monthly

### 10.2 月次精算

- 前月分を対象に生成する
- StoreLedgerEntry.occurred_at を基準に集計する
- 店舗取り分は gross_yen の70%
- 1円未満は floor
- 最低支払額は10,000円
- 10,000円未満の場合は Settlement を作らず SettlementCarryover に繰り越す
- 繰越額は次回支払可能時に最初の Settlement に加算する

### 10.3 手動精算

- 指定期間で作成する
- 期間重複がある場合は作成しない
- 作成時点で confirmed になる

### 10.4 精算状態

```text
draft / confirmed / exported / paid
```

### 10.5 CSV出力

- 住信SBI 総合振込CSVを出力する
- confirmed の Settlement のみ出力対象
- manual_bank の active な振込先口座が必要
- CSV出力時に Settlement.status は exported になる
- 振込先口座情報は Settlement にスナップショット保存する

---

## 11. 実装上の重要ルール

- ドリンク送信、消化、返金はトランザクション内で整合性を保つ
- pending ドリンクは FIFO で消化する
- 配信終了時に未消化ドリンクは自動返金される
- 売上確定の唯一の根拠は StoreLedgerEntry
- 精算集計の基準日時は StoreLedgerEntry.occurred_at
- Stage は Booth 固定で、StreamSession はコピーを保持する
