# Settlement Lifecycle

## 1. この文書の位置づけ

この文書は、精算作成、確定、振込CSV出力、支払済み化、支払明細書PDF、銀行API振込の扱いを整理するための正本ドキュメントである。

現状把握では実コードを正として扱う。ただし、現在の実コードが今後も正しいという意味ではなく、実コードと既存ドキュメントの差分は後続Issueでどちらに寄せるかを決める。

この文書は以下の実コードを確認して作成している。

- `app/models/settlement.rb`
- `app/models/settlement_event.rb`
- `app/models/settlement_export.rb`
- `app/models/settlement_carryover.rb`
- `app/models/store_payout_account.rb`
- `app/models/store_ledger_entry.rb`
- `app/controllers/admin/settlements_controller.rb`
- `app/controllers/system_admin/settlements_controller.rb`
- `app/controllers/system_admin/settlement_exports_controller.rb`
- `app/services/settlements/monthly_generate_service.rb`
- `app/services/settlements/manual_preview_service.rb`
- `app/services/settlements/manual_create_service.rb`
- `app/services/settlements/month_period.rb`
- `app/services/settlements/sbi_furikomi_csv_export_service.rb`
- `app/services/payout_accounts/jp_bank_converter.rb`
- `config/routes.rb`
- `config/recurring.yml`
- `app/jobs/`

関連Issue:

- Epic: #925
- この文書追加: #926
- paid日時・操作者: #927
- confirmed以降の固定: #928
- 振込先スナップショット: #929
- CSV出力不整合: #930
- 手動精算: #931
- 月次精算導線: #932
- PDF生成方式: #933
- 支払明細書PDF: #934
- 銀行API振込対象外整理: #935

---

## 2. 現行ライフサイクル

現行実装の精算状態は以下である。

```text
draft / confirmed / exported / paid
```

現行実装の状態遷移は以下である。

```mermaid
stateDiagram-v2
  [*] --> draft: monthly settlement
  [*] --> confirmed: manual settlement
  draft --> confirmed: system_admin confirm
  confirmed --> exported: SBI CSV export
  exported --> paid: system_admin mark_paid
```

現行実装では `confirmed -> paid` の直接遷移は提供していない。`SystemAdmin::SettlementsController#mark_paid` は `exported` の精算のみを対象にしている。

---

## 3. 状態の意味

### 3.1 draft

月次精算で作成される仮作成状態である。

現行実装では、`Settlements::MonthlyGenerateService` が `status: :draft` の `Settlement` を作成する。

### 3.2 confirmed

運営側で確定済みの状態である。

現行実装では以下の経路で作成または遷移する。

- 月次精算の `draft` を system_admin が `confirm` する
- 手動精算を `Settlements::ManualCreateService` が `confirmed` として作成する

CSV出力対象は `confirmed` のみである。

### 3.3 exported

振込CSVを生成済みの状態である。

`exported` は銀行振込成功を意味しない。現行実装では、住信SBIの総合振込CSVを生成し、`SettlementExport` とCSVファイルを保存し、対象 `Settlement` を `exported` に更新した状態である。

CSV出力時に、店舗の active な `manual_bank` 振込先を `Settlement` へスナップショット保存する。
このスナップショットは、`exported` 以降の支払・監査・支払明細書PDFで参照する振込先の正本であり、保存後は変更しない。

### 3.4 paid

正式な支払済み状態である。

支払明細書PDFの正式な対象は `paid` の精算のみとする。

現行実装では、system_admin が `exported` の精算詳細画面で「銀行アップロード/支払実行を確認した」にチェックし、`mark_paid` を実行すると `paid` になる。

`mark_paid` 実行時に `settlements.paid_at` と `settlements.paid_by_user_id` を保存する。支払日として使う正本は `Settlement.paid_at` であり、手動で支払済みにした操作者は `Settlement.paid_by_user` で参照する。

---

## 4. 売上集計と金額

### 4.1 売上集計の正

売上集計の正は `StoreLedgerEntry` である。

`StoreLedgerEntry` は `DrinkOrder` が `consumed` になった時点で作成される。未消化の `pending` ドリンクや返却済みの `refunded` ドリンクは `StoreLedgerEntry` を作らないため、精算集計には含めない。

集計基準日時は `StoreLedgerEntry.occurred_at` である。

### 4.2 月次精算

月次精算は `Settlements::MonthlyGenerateService` が処理する。

現行実装の主なルール:

- 実行導線は system_admin の精算一覧からの手動実行
- URLは `POST /system_admin/settlements/generate_monthly`
- system_admin 画面からの実行対象はJST基準の前月
- `StoreLedgerEntry.occurred_at` を基準に集計する
- 既存 `Settlement` と重複する期間は除外する
- 店舗取り分は `gross_yen * 0.7` の floor
- `platform_fee_yen` は `gross_yen - store_share_yen`
- 最低支払額は10,000円
- 支払可能額が10,000円未満の場合、`Settlement` は作らず `SettlementCarryover` に繰り越す
- 繰越がある場合、次回支払可能時の最初の `Settlement` に加算し、相殺用の負の `SettlementCarryover` を作成する
- system_admin から実行した場合、作成された `Settlement` ごとに `SettlementEvent.created` を記録する
- system_admin 画面の実行結果では、`Settlement` 作成、最低支払額未満による繰越、その他スキップを分けて表示する

production（本番環境）での月次精算自動実行は #275 で Rake task（Railsタスク）と systemd timer（Linux の定期実行機能）テンプレートとして整理する。system_admin 画面からの手動生成導線は #932 のまま残す。`config/recurring.yml`、`app/jobs`、ActiveJob（Railsの非同期ジョブ）は使わない。

`Settlement` が作られないスキップ結果は `SettlementEvent` に記録しない。最低支払額未満の繰越は `SettlementCarryover` に記録する。`SettlementEvent` は `Settlement` に紐づく操作履歴であり、繰越のみの処理では紐づけ先の `Settlement` が存在しないためである。既存精算との重複除外は月次生成結果のスキップ件数として扱う。

### 4.3 手動精算

手動精算は `Settlements::ManualCreateService` が処理し、作成時点で `confirmed` になる。

手動精算はテスト・例外確認用の精算として扱い、繰越は適用しない。繰越の適用と相殺用の `SettlementCarryover` 作成は月次精算で扱う。

`ManualPreviewService` が表示する `gross_yen` / `store_share_yen` / `platform_fee_yen` と、`ManualCreateService` が作成する `Settlement` の金額は一致する。

---

## 5. 振込先スナップショット

店舗振込先は `StorePayoutAccount` に保存される。

現行実装では、振込先スナップショットは `confirmed` 時点ではなく、CSV出力によって `exported` になる時点で `Settlement` に保存される。
今回の見直しでは、現行CSV運用を前提に、`exported` 時点のスナップショットを正本として扱う。
`exported` 以降の `Settlement` では、以下のスナップショットカラムを変更不可にする。

スナップショット対象の主なカラム:

- `payout_bank_code`
- `payout_branch_code`
- `payout_account_type`
- `payout_account_number`
- `payout_account_holder_kana`

支払明細書PDFや運営側の監査表示では、現在の `StorePayoutAccount` ではなく `Settlement` 側のスナップショットを参照する。

`StorePayoutAccount` が後から変更されても、過去に `exported` になった `Settlement` の振込先スナップショットは変わらない。

---

## 6. CSV出力

CSV出力は `Settlements::SbiFurikomiCsvExportService` が処理する。

現行実装の主なルール:

- 対象は `confirmed` の `Settlement` のみ
- 店舗に active な `manual_bank` の `StorePayoutAccount` が必要
- CSV生成の主導線は `SystemAdmin::SettlementsController#export_csv`
- `SystemAdmin::SettlementExportsController` は生成済みCSVの `index` / `show` のみを扱う
- 1ファイル最大9,999件を上限とし、超過時は分割せずエラーとして扱う
- `StorePayoutAccount.account_type` が `ordinary` の場合はCSV口座種別 `1`、`current` の場合は `2` として出力する
- CSV生成後に `SettlementExport` を作成し、CSVファイルをActiveStorageに添付する
- 対象 `Settlement` を `exported` に更新する
- 対象 `Settlement` に振込先スナップショットを保存する
- `SettlementEvent.exported` を記録する
- CSV生成中に例外が発生した場合、対象 `Settlement` に `SettlementEvent.export_failed` を記録し、呼び出し元には `ok: false` を返す
- 事前条件不一致による早期エラー、たとえば `confirmed` 以外や振込先未設定は、CSV生成失敗ではなく入力不備として扱う

---

## 7. 支払済み化

現行実装では、`paid` への遷移は `SystemAdmin::SettlementsController#mark_paid` が行う。

主なルール:

- 対象は `exported` の `Settlement` のみ
- system_admin が確認チェックを入れた場合のみ実行する
- `Settlement.status` を `paid` に更新する
- `Settlement.paid_at` に支払済み化した日時を保存する
- `Settlement.paid_by_user` に操作したsystem_adminを保存する
- `SettlementEvent.marked_paid` を記録する

現行実装には以下がない。

- `paid_source`
- paid後の取消・再精算の仕組み

`Settlement` は `paid` 精算に `paid_at` を必須としている。`paid_by_user_id` は手動 `mark_paid` では保存するが、将来の銀行API結果による自動 paid 化では nil または system user 扱いを許容する余地を残す。

---

## 8. 支払明細書PDF

支払明細書PDFは、精算ライフサイクルの出口として扱う。

正式な支払明細書PDFの対象は `paid` の `Settlement` のみとする。

想定する出力:

- 店舗管理者向け: 支払明細書
- system_admin向け: 支払明細書（運営控え）

PDFで参照する正本データ:

- 金額: `Settlement` の金額カラム
- 対象期間: `Settlement.period_from` / `Settlement.period_to`
- 支払日: `Settlement.paid_at`
- 振込先: `Settlement` の振込先スナップショット

PDF生成方式は `docs/design/payment_statement_pdf.md` で定める。実装は #934 で扱う。

---

## 9. 銀行API振込とPhase1運用

住信SBIネット銀行へAPI連携による振込サービスについて問い合わせた結果、現時点ではAPI連携での振込サービスは行っていないとの回答を受領した。

そのため、Phase1では銀行API振込は対象外とする。

Phase1の正規運用は以下である。

```text
confirmed
  -> 住信SBI総合振込CSV出力
  -> exported
  -> 銀行画面へ手動アップロード
  -> 銀行側で振込実行確認
  -> system_admin が手動で paid 化
  -> paid
```

方針:

- `Settlement.status` は `draft / confirmed / exported / paid` の精算ライフサイクルを表すものとして維持する
- 銀行処理状態を `Settlement.status` に追加しない
- `exported` はCSV生成済みであり、銀行振込成功を意味しない
- `paid` は正式な支払済み状態であり、支払明細書PDFの対象である
- `SettlementPayoutBatch` / `SettlementPayoutItem` は現時点では作らない
- 将来、別銀行・振込代行・決済代行などを採用する場合に、API振込用モデルを改めて検討する

将来API振込を検討する場合の論点は `docs/design/payout_api_design.md` を参照する。

---

## 10. 既存ドキュメントとの差分

現行実装と既存ドキュメントの主な差分は以下である。

| 項目 | 既存ドキュメント | 現行実コード | 方針 |
| --- | --- | --- | --- |
| `confirmed -> paid` | 記載あり | 実装なし。`mark_paid` は `exported` のみ | 現行実装を正として扱い、必要なら後続Issueで仕様判断する |
| confirmed以降の固定 | 金額・振込先情報を固定すると記載 | 金額・期間はモデル上で変更不可。振込先情報は #929 で整理する | #928 / #929 で整理する |
| 振込先スナップショット | confirmed時点と読める記述あり | CSV出力時、`exported` 時点で保存。`exported` 以降は変更不可 | #929 で `exported` 時点の正本として明確化する |
| 支払日 | 未整理 | `paid_at` を保存し、`paid` 精算では必須 | 現行実装を正として扱う |
| API振込 | 未整理 | 未実装。住信SBIネット銀行では現時点でAPI連携による振込サービスを利用できない | #935 ではPhase1対象外として記録し、CSV出力 + 銀行画面アップロード + 手動 `paid` 化を正規運用として明文化する |

---

## 11. 月次精算生成の定期実行（#275）

月次精算生成は `Settlements::MonthlyGenerateService` を正とし、system_admin 画面からの手動実行導線（#932）に加えて、production（本番環境）では systemd timer（Linux の定期実行機能）から Rake task（Railsタスク）を実行する。

通常実行:

```bash
bin/rails settlements:monthly_generate
```

通常実行では JST 基準の前月分を対象にする。systemd timer は EC2 の UTC 運用に合わせ、毎月1日 `04:00 UTC`、つまり `13:00 JST` に実行する。

救済用に任意月指定も許可する。

```bash
bin/rails "settlements:monthly_generate[2026-05]"
```

この task は `monthly / draft` の `Settlement` 作成、最低支払額未満の `SettlementCarryover` 作成、既存精算との重複スキップを `MonthlyGenerateService` の現行仕様どおりに処理する。`confirmed`、CSV出力、`paid` 化、支払明細書PDF発行は自動化しない。

systemd / Rake task 実行では操作ユーザーが存在しないため、`actor_user: nil` のまま Service を呼び出す。したがって `SettlementEvent.created` は記録しない。`SettlementEvent.created` を記録するのは、system_admin 画面から手動実行された場合のみとする。

Rake task は systemd / journalctl で確認できるよう、対象期間、作成件数、繰越件数、スキップ件数を標準出力に出す。

```text
[MonthlySettlement] target=2026-05-01..2026-06-01 created=0 carryover=1 skipped=0
```

systemd の service / timer テンプレートと運用手順は以下を正とする。

- `ops/systemd/butterflyve-monthly-settlement.service`
- `ops/systemd/butterflyve-monthly-settlement.timer`
- `docs/ops/monthly_settlement_timer.md`

`config/recurring.yml`、`app/jobs`、ActiveJob（Railsの非同期ジョブ）、DB上のバッチ実行ログテーブルは #275 では使わない。

---

## 12. 守る前提

- 金銭処理・状態変更は Service に集約する
- Controller は認可、Service 呼び出し、レスポンスに留める
- DB transaction は Service 側で扱う
- 売上集計の正は `StoreLedgerEntry`
- 未消化・返却済みドリンクを売上に含めない
- `paid` を正式な支払済み状態として扱う
- `exported` を銀行振込成功とは扱わない
