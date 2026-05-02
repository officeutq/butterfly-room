# Architecture（現行実装確定版）

## 1. 概要

本システムは Rails 8 + Hotwire をベースとしたモノリシック構成である。
業務処理は Service 層に分離されており、Controller は認証・認可・入力受付・レスポンス制御を担当する。

---

## 2. 基本レイヤ

```text
Controller
  ↓
Service
  ↓
ActiveRecord Model
  ↓
PostgreSQL
```

---

## 3. Controller の責務

- 認証
- 認可
- パラメータ受付
- Service 呼び出し
- Turbo / JSON / HTML レスポンス

ApplicationController では全体に authenticate_user! が設定されている。
例外ページは各Controllerで skip_before_action する設計である。

---

## 4. Service の責務

Service は複数モデルをまたぐ業務処理とトランザクション境界を担当する。

主要Service:

- StreamSessions::StartService
- StreamSessions::StatusService
- StreamSessions::EndService
- StreamSessions::ForceEndService
- Ivs::CreateParticipantTokenService
- DrinkOrders::CreateService
- DrinkOrders::ConsumeService
- DrinkOrders::RefundService
- Wallets::HoldService
- Wallets::ConsumeService
- Wallets::ReleaseService
- Wallets::ApplyPurchaseFromStripeService
- Settlements::MonthlyGenerateService
- Settlements::ManualCreateService
- Settlements::SbiFurikomiCsvExportService

---

## 5. 配信アーキテクチャ

### 5.1 Stage管理

IVS Stage は Booth に固定で紐づく。
StreamSession は配信開始時に booth.ivs_stage_arn をコピーする。

Token発行リクエストをトリガーに Stage を作成しない。

### 5.2 配信状態

Booth.status がUI・参加可否の主要な状態として使われる。
StreamSession はセッション実体と終了状態を持つ。

### 5.3 Publisher / Viewer

Publisher は standby / live / away で参加可能。
Viewer は live / away のみ参加可能。

---

## 6. ドリンク・ウォレット処理

### 6.1 ドリンク作成

DrinkOrders::CreateService が以下を同一トランザクションで処理する。

- Wallets::HoldService
- DrinkOrder 作成
- WalletTransaction hold 作成
- Comment drink 作成

### 6.2 ドリンク消化

DrinkOrders::ConsumeService が以下を同一トランザクションで処理する。

- DrinkOrder lock
- FIFO guard
- hold transaction 確認
- Wallets::ConsumeService
- DrinkOrder consumed 更新
- StoreLedgerEntry 作成

### 6.3 ドリンク返金

DrinkOrders::RefundService が、StreamSession 内の pending DrinkOrder を一括返金する。
配信終了時に EndService から呼ばれる。

---

## 7. 精算アーキテクチャ

### 7.1 集計基準

StoreLedgerEntry.occurred_at をSSOTとして集計する。

### 7.2 月次精算

Settlements::MonthlyGenerateService が以下を行う。

- 前月期間を算出
- StoreLedgerEntry を店舗別集計
- 既存Settlementと重複しないgapを算出
- 店舗取り分70%を計算
- 10,000円未満は SettlementCarryover に繰越
- 支払可能額に達した場合は Settlement を作成

### 7.3 CSV出力

Settlements::SbiFurikomiCsvExportService が confirmed の精算を対象に住信SBI CSVを作成する。
CSV出力時に Settlement.status を exported にし、振込先情報をスナップショット保存する。

---

## 8. トランザクション境界

重要なトランザクション境界:

- 配信開始
- 配信終了
- ドリンク送信
- ドリンク消化
- ドリンク返金
- ポイント購入反映
- 月次精算作成
- CSV出力時のSettlement更新

---

## 9. 現行設計上の注意点

- Booth.status と StreamSession.status は完全な単一責任ではない
- 視聴可否は Booth.status に強く依存する
- StreamSession.status は作成時 live だが、Booth は standby になる
- 今後、状態管理の正本を整理すると保守性が上がる
