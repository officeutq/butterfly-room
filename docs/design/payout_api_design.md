# Payout API Design

## 1. この文書の位置づけ

この文書は、精算ライフサイクルEpic #925 の子Issue #935 に対応し、銀行API（外部システム連携用の窓口）振込の扱いと、Phase1のCSV（銀行アップロード用の表形式ファイル）振込運用を整理するための設計メモである。

現時点では、銀行API振込の実装準備ではなく、以下を明確にする。

- 住信SBIネット銀行では、現時点でAPI連携による振込サービスを利用できない。
- Phase1では、住信SBI総合振込CSV出力、銀行画面への手動アップロード、system_admin による手動 `paid`（支払済み）化を正規運用とする。
- `SettlementPayoutBatch`（将来の精算支払い依頼単位） / `SettlementPayoutItem`（将来の精算支払い明細単位）は今すぐ作らない。
- 将来、別銀行・振込代行・決済代行などを採用する場合に、API振込用のモデルを改めて検討する余地を残す。

---

## 2. 住信SBIネット銀行からの回答

住信SBIネット銀行へAPI連携による振込サービスについて問い合わせた結果、以下の回答を受領した。

```text
現在当社ではAPI連携でのお振込のサービスは行っておりません。
```

このため、住信SBIネット銀行のAPI振込を前提にした実装、外部通信、モデル追加は現時点では行わない。

---

## 3. 現行運用

現行の正本は実コードである。

主な実装:

- `app/models/settlement.rb`
- `app/models/settlement_export.rb`
- `app/controllers/system_admin/settlements_controller.rb`
- `app/controllers/system_admin/settlement_exports_controller.rb`
- `app/services/settlements/sbi_furikomi_csv_export_service.rb`
- `app/services/settlements/mark_paid_service.rb`

現行運用:

1. system_admin が `confirmed` の `Settlement` を選択する。
2. `Settlements::SbiFurikomiCsvExportService` が住信SBI向け総合振込CSVを1ファイル生成する。
3. CSVファイル単位は `SettlementExport` として保存する。
4. CSV出力時に対象 `Settlement` は `exported` になる。
5. CSV出力時点の振込先口座情報を `Settlement` にスナップショット保存する。
6. system_admin が銀行画面へCSVを手動アップロードする。
7. 銀行側で振込実行を確認した後、system_admin が精算詳細画面で手動で `paid` 化する。
8. `paid` 後に支払明細書PDFを発行できる。

`exported` はCSV生成済みを表し、銀行振込成功を意味しない。

---

## 4. 現時点で存在しないもの

現行実装には、銀行API振込を前提にした以下の情報やモデルはない。

- 銀行API依頼ID
- 銀行側受付状態
- 銀行側の成功 / 失敗結果
- API再試行状態
- 個別明細ごとの振込状態
- idempotency key（冪等性キー。二重実行を防ぐための識別子）
- API振込用の batch / item モデル

これらを `Settlement.status` に追加することもしない。

---

## 5. Phase1方針

Phase1では、API振込は対象外とする。

Phase1の正規運用:

```text
confirmed
  -> 住信SBI総合振込CSV出力
  -> exported
  -> 銀行画面へ手動アップロード
  -> 銀行側で振込実行確認
  -> system_admin が手動で paid 化
  -> paid
  -> 支払明細書PDF発行
```

方針:

- `Settlement.status` は `draft / confirmed / exported / paid` の精算ライフサイクルを表すものとして維持する。
- 銀行処理状態を `Settlement.status` に追加しない。
- `exported` はCSV生成済みであり、銀行振込成功を意味しない。
- `paid` は正式な支払済み状態である。
- 住信SBI CSV運用をPhase1の本線として扱う。
- API振込による `paid` 自動化は行わない。
- `SettlementPayoutBatch` / `SettlementPayoutItem` は今回作らない。

---

## 6. 今回作らない理由

`SettlementPayoutBatch` / `SettlementPayoutItem` を今すぐ作らない理由:

- 住信SBIネット銀行では現時点でAPI連携による振込サービスを利用できない。
- 具体的な provider（銀行・振込代行・決済代行などの提供元）が未定である。
- provider が未定の状態でモデル名、カラム、状態遷移を確定すると、将来の実サービス仕様とずれる可能性が高い。
- Phase1の運用はCSV出力と手動 `paid` 化で成立している。
- 先に抽象モデルだけを作ると、使われない状態や責務の不明確なモデルが残るリスクがある。

そのため、現時点では設計メモに留める。

---

## 7. 将来API対応時の検討論点

将来、別銀行・振込代行・決済代行などを採用してAPI振込を検討する場合は、以下を改めて整理する。

- provider（銀行・振込代行・決済代行などの提供元）
- method（API / CSV / 手動などの実行方式）
- batch単位の依頼ID
- item単位の振込結果
- idempotency key（冪等性キー。二重実行を防ぐための識別子）
- 二重振込防止
- 部分失敗
- 再試行
- `paid` 化条件
- CSV運用との共存
- 監査ログ
- エラー時の運用

将来候補として `SettlementPayoutBatch` / `SettlementPayoutItem` のような精算支払い専用モデルを検討してよい。ただし、現時点ではモデル名、カラム、状態 enum を確定しすぎない。

---

## 8. 将来API対応時に守る境界

将来API振込を追加する場合でも、以下の境界は維持する。

- `Settlement.status` は精算ライフサイクルを表す。
- 銀行・振込代行・決済代行側の受付状態、失敗理由、再試行状態は `Settlement.status` に詰め込まない。
- 金銭処理・状態変更は Service（業務処理を集約するクラス）に集約する。
- Controller（リクエストを受ける層）は認可、Service呼び出し、レスポンスに留める。
- DB transaction（データベースの一連処理）は Service 側で扱う。
- `paid` 化条件は、CSV運用とAPI運用の両方で明確に定義する。
- 二重振込防止と監査ログを実装前に設計する。

---

## 9. このIssueでやらないこと

#935 では以下を行わない。

- `SettlementPayoutBatch` / `SettlementPayoutItem` のモデル追加
- migration追加
- 銀行API通信
- 外部通信
- 実振込
- `paid` 自動化
- CSV運用の置き換え
- provider未定のままの詳細カラム設計

---

## 10. 将来実装時のテスト観点

このIssueでは実装テストは不要である。

将来API振込を実装する場合は、少なくとも以下をテストする。

- CSV運用を壊さない
- 二重振込防止
- 冪等性
- 部分失敗
- 再試行
- `paid` 化条件
- 権限
- 監査ログ

---

## 11. 結論

Phase1では、銀行API振込は対象外とする。

住信SBIネット銀行向けには、現行のCSV出力、銀行画面への手動アップロード、system_admin による手動 `paid` 化を正規運用とする。

API振込用モデルは現時点では追加しない。将来、API振込に対応できる別サービスを採用する場合に、provider、method、冪等性、二重振込防止、部分失敗、再試行、`paid` 化条件を改めて設計する。
