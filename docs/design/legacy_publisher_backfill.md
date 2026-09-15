# 終了済み旧配信の作成者補完（#1289）

## 対象と意味

`StreamSessions::LegacyPublisherBackfillService` と `stream_sessions:backfill_legacy_publishers` を使用する。カラム追加のmigrationでは実行しない。新しい配信制御の共通有効化とは別の、明示的なデータ補完である。

DBの基準時刻に終了済みで、開始・終了時刻が整合し、実配信者の新列が空、現在のブースから参照されない旧配信だけに、準備作成者Xを設定する。`actual_publisher_source=legacy_creator_backfill` は合意した旧履歴の帰属方針を表し、Xが実際に配信した証拠ではない。2026-09-15に旧履歴はこのX補完へ統一し、IVSの過去履歴による人物調査・補正は今回の対象から外すことをユーザーが決定した。対象条件・固定一覧・既存記録を上書きしない条件は維持する。

次の新列だけを更新する。元のX、開始・終了時刻、状態、店舗・ブース、`updated_at`、台帳、ドリンク、返却、精算、保存済みコメントは変更しない。

- `actual_publisher_user_id`：固定一覧のX。
- `actual_publisher_source`：`legacy_creator_backfill`。
- `actual_publisher_recorded_at`：各行を適用した時刻。
- `actual_publisher_evidence`：一覧のSHA-256（内容を識別するハッシュ）、実行コードのcommit、上記新列の変更前後。

## 固定一覧と事前確認

`plan` は PostgreSQL の Repeatable Read（同じ時点のデータを読むトランザクション）に `READ ONLY` を指定する。DB側の基準時刻、最大セッションID、対象ID、変更前の値、補完後の人物、集計への影響、除外ID・理由をJSONファイルへ保存する。既存ファイルへの上書きは拒否する。

適用・復旧はこの同じファイルを使う。対象を再検索して増やさない。対象条件が変わったからといって再度`plan`を実行し、基準時刻を後ろへ動かさない。必要な再計画は別の適用判断として扱う。

一覧の整合性をSHA-256で確認し、実行時には確認済みのSHA-256を明示する。これは改変検出と一覧の取り違え防止であり、署名や承認者の認証ではない。一覧・確認記録・実行ログを一緒に保管する。

Rails環境名と、DB接続先のadapter/host/port/databaseをハッシュ化した値も照合する。別環境の一覧は使用できない。同じDBでも接続経路を変えると一致しないため、事前確認と適用・復旧は同じ接続設定で実行する。パスワード、メール、氏名、トークンは一覧へ出力しない。除外行の任意の既存evidenceも出力しない。

| 除外理由 | 対象 |
| --- | --- |
| `existing_publisher_record` | 人物・由来・記録時刻または既存evidenceがある。別の記録として保持 |
| `not_ended` | 準備中・配信中・離席中など、終了済みではない |
| `missing_broadcast_start` | 開始時刻がない。未配信の確証とは扱わず、推定しない |
| `inconsistent_end` | 終了時刻がない、または開始より前 |
| `outside_cutoff` | 基準時刻より後に作成・終了 |
| `current_reference` | いずれかのブースの現在セッションとして参照される |

`impact` は各セッションの全期間の消化台帳ポイント・件数と開始から終了までの秒数を示す。新方式での不明行からXへ帰属を移す見込みであり、月次金額や丸め後の支払差額ではない。店舗・ブースのポイント総額は変わらない。実画面の確認は対象期間ごとの `CastMetricsQuery` でも行う。既存の精算率・丸めを再計算し直さない。

## 実行手順

以下はローカルDockerのPowerShell例。環境名とファイルは対象環境ごとに分ける。ステージング・本番へそのまま実行する指示ではない。本番の具体的一覧・差分の適用確認は #1288 の確認記録に残す。

```powershell
$backfillCommit = git rev-parse HEAD
docker compose exec -T -e "PUBLISHER_BACKFILL_GIT_COMMIT=$backfillCommit" -e PUBLISHER_BACKFILL_MANIFEST=tmp/publisher-backfill-local.json app bin/rails stream_sessions:backfill_legacy_publishers
```

1. `plan` が正常終了したことを確認する。対象・除外・基準時刻・集計影響を確認し、一覧と適用判断を保管する。エラー時の空ファイルを正常な一覧と扱わない。
2. 対象環境・DBが正しいことを確認し、更新前の新列と関連金額を保全する。
3. 確認した一覧のSHA-256を指定して適用する。Git commitは実行コードの値を記録する。

```powershell
$backfillHash = (Get-Content -Raw tmp/publisher-backfill-local.json | ConvertFrom-Json).sha256
docker compose exec -T -e "PUBLISHER_BACKFILL_GIT_COMMIT=$backfillCommit" -e PUBLISHER_BACKFILL_MODE=apply -e PUBLISHER_BACKFILL_MANIFEST=tmp/publisher-backfill-local.json -e "PUBLISHER_BACKFILL_CONFIRM_SHA256=$backfillHash" app bin/rails stream_sessions:backfill_legacy_publishers
```

4. `applied`・`already_applied`・`skipped_*` の件数とIDを確認する。終了コード0でも `skipped_*` は未適用として残す。変更前値の変化、現在参照、台帳ポイント・件数の変化、対象の欠落は自動で解消しない。
5. 元のX・時刻・状態と金額が変わらないこと、対象の表示・個人別集計だけが予定どおり変わることを確認する。新方式が無効なら画面は既存のX参照のままであり、表示が同じことだけで補完成功と判定しない。

## 中断・競合・復旧

1行ごとにブース→セッションの順にロックし、元の値と条件を再検証してから保存する。予期しないDBエラーではその行を取り消して停止する。それまでに確定した行は残る。行別ログはcommit後に出力するため、ログ出力中の停止も同じ一覧で再開できる。

再開は同じ`apply`コマンドを使う。同じ一覧による適用済み行は `already_applied` とし、最初の記録時刻・evidenceを変えない。新規作成・後から終了したセッションは増えない。他の人物・根拠への変更は `skipped_changed` とし、上書きしない。

復旧は同じ一覧・確認SHA-256で `PUBLISHER_BACKFILL_MODE=restore` を指定する。現在の新列とevidenceがこの一覧の適用後値に一致し、元の履歴項目にも変更がない行だけを更新前の新列へ戻す。復旧済み行は `already_restored`、後から証拠補正された行・履歴が変わった行は `skipped_changed` とする。現在参照のある行も戻さない。ファイルから対象を削る、チェックサムを書き換えて強制適用する、といった復旧はしない。

## 検証・実環境の記録

テストは事前確認のDB書き込み拒否、対象外の非変更、適用・再実行・commit後中断、途中DB失敗、同時実行のロック待ち、変更済み値の保護、復旧、CLIの上書き拒否を確認する。表示・個人集計の不明→X→不明と、台帳・未消化／返却・精算・コメントの完全一致も確認する。

2026-09-14 17:17:50 JST、ローカル開発DBに`plan`だけを実行した（コード`fbc7af9`）。最大ID 770、補完対象62件、開始記録なし645件、未終了27件。対象の全期間ポイント25,301、配信秒数14,953,270。対象62件も含め、開発DBには未適用である。終了時刻等の記録値をそのまま使う集計であり、実配信者を証明した結果ではない。

固定一覧は`tmp/publisher-backfill-local-20260914.json`、SHA-256は`5c6731a291ad2f7b4119924dcc8dea905a0756a25cd73879e5e685750815e811`。ID別の一覧はローカルファイルに保持し、公開文書へ人物情報を転載しない。関連45テスト291検証は成功した。

テストDBへの適用・復旧と、実環境への適用を区別する。上記事前確認時点ではステージング・本番は未調査・未適用。その後の2026-09-14のDB読み取り結果は [旧履歴の調査結果](legacy_publisher_evidence.md) を参照する。3環境とも未補完で、実環境への適用と直前の状態確認は #1288・親 #1280 に残す。
