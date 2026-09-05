# 既存画像を新方式へ移行する運用手順

## 1. 目的と実行順

実装前から存在するUser `avatar`、Store `thumbnail`、Booth `thumbnail_image`を、用途別の編集元JPEG、固定寸法の表示用JPEG、crop dataへ移行する。既存Blobのキーは上書きせず、編集元と表示用をそれぞれ別Blob・別キーへ物理複製する。

実環境では次のIssueを順番に完了し、前段の結果を確認するまで次へ進まない。

1. #1162 ステージングdry-run
2. #1163 ステージング少数件applyと通常画面確認
3. #1164 ステージング全件applyと照合
4. #1165 本番dry-runと対象承認
5. #1166 本番applyと事後照合

#1161ではService（移行処理を集約するクラス）とtaskの実装・ローカルDiskテストだけを行い、ステージング・本番では実行しない。

## 2. 対象と生成規則

| 移行前添付 | 用途 | 編集元 | 表示用 | crop |
| --- | --- | --- | --- | --- |
| User `avatar` | cover | `cover_image_source` | `cover_image` 1200×630 | 中央40:21 |
| User `avatar` | avatar | `avatar_source` | `avatar` 1024×1024 | 中央1:1 |
| Store `thumbnail` | thumbnail | `thumbnail_source` | `thumbnail` 1200×630 | 中央40:21 |
| Booth `thumbnail_image` | thumbnail | `thumbnail_image_source` | `thumbnail_image` 1200×630 | 中央40:21 |

Userは必ずcoverを先に1 transaction（データベースの一連処理）で確定し、成功または移行済みを確認してからavatarを別transactionで確定する。途中停止しても、両用途の生成元は移行前の同じavatar Blobになる。coverが部分状態または生成失敗ならavatarを変更しない。

既に新方式のavatar画像組が完全なUserは、通常フォームで更新済みと判断する。coverが未設定でも、バッチが新しいavatarからcoverを自動生成しない。

編集元は次の契約へ正規化する。

- JPEG、品質0.94相当、sRGB、透過は白背景、向きを反映し、EXIF等のメタデータを除去
- 入力は20MiB・長辺8192px・3200万画素・縦横比8:1以下
- 編集元は長辺4096px・800万画素以下
- 用途の最低寸法に足りない画像は上限内で等比拡大
- 最低寸法と上限を両立できない画像は`failed_invalid_image`

生成後は通常更新と同じ`PairValidator`、一時Blob、保存先存在確認、レコードロック、期待ID照合、`StagedPairUpdateService`を通す。

## 3. taskと共通環境変数

task名は`image_attachments:migrate_legacy_pairs`。指定がなければ必ずdry-runとなる。

| 環境変数 | 内容 |
| --- | --- |
| `IMAGE_MIGRATION_RECORD_TYPE` | `User` / `Store` / `Booth`。省略時は全種別 |
| `IMAGE_MIGRATION_RECORD_ID` | 1レコードに限定。`RECORD_TYPE`も必須 |
| `IMAGE_MIGRATION_MIN_ATTACHMENT_ID` | 対象attachment IDの下限（含む） |
| `IMAGE_MIGRATION_MAX_ATTACHMENT_ID` | 対象attachment IDの上限（含む） |
| `IMAGE_MIGRATION_AFTER_ATTACHMENT_ID` | 指定IDより後から再開 |
| `IMAGE_MIGRATION_LIMIT` | 1回に選択する移行前attachment件数 |
| `IMAGE_MIGRATION_EXPECTED_ATTACHMENT_ID` | 個別実行時の期待attachment ID |
| `IMAGE_MIGRATION_EXPECTED_BLOB_ID` | 個別実行時の期待Blob ID |
| `IMAGE_MIGRATION_GIT_COMMIT` | 実行中イメージのGit SHA。applyでは必須 |
| `IMAGE_MIGRATION_APPLY` | `true` / `1`でapply。それ以外はdry-run |
| `IMAGE_MIGRATION_CONFIRM` | apply時だけ固定値`APPLY_LEGACY_IMAGE_PAIR_MIGRATION` |

applyでは`LIMIT`が必須。全体・範囲実行はdry-runで確定した`MAX_ATTACHMENT_ID`も必須とし、実行中に追加された添付を巻き込まない。個別実行は`RECORD_TYPE`、`RECORD_ID`、2つの期待IDを必須とする。

## 4. JSON Linesの保管

標準出力は先頭1行がsummary、以降が用途単位のentryとなる。ファイル名、S3キー、署名URL、画像、メールアドレス等の個人情報は出力しない。

レポートはリポジトリ外のアクセス制限されたディレクトリに保存する。次は対象EC2上での例であり、composeファイルと環境ファイルは対象環境のデプロイ手順に合わせる。

```bash
MIGRATION_REPORT_DIR=/opt/butterfly-room/reports/image-pair-migration
install -d -m 700 "$MIGRATION_REPORT_DIR"
umask 077
```

出力後にmodeが600であること、先頭から末尾まで各行がJSONとして読めることを確認する。レポートをGit管理下、共有チャット、公開Issueへ添付しない。

本番の事後照合完了日から90日保持する。削除前に、未解決対象のrecord type・record ID・purpose・statusだけを個別Issueへ転記したことを確認する。件数、status別集計、実行commit、実行期間の要約は運用Issueへ残す。

## 5. dry-run

最初に件数制限なしのdry-runで対象総数と最大attachment IDを確定する。画像のダウンロードと変換検査は行うが、Blob、Attachment、crop dataを変更しない。

```bash
MIGRATION_GIT_COMMIT=$(git rev-parse HEAD)
MIGRATION_REPORT_FILE="$MIGRATION_REPORT_DIR/dry-run-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

docker compose -f docker-compose.staging.yml run --rm \
  -e IMAGE_MIGRATION_GIT_COMMIT="$MIGRATION_GIT_COMMIT" \
  app bin/rails image_attachments:migrate_legacy_pairs \
  > "$MIGRATION_REPORT_FILE"

chmod 600 "$MIGRATION_REPORT_FILE"
```

負荷確認の最初の1回は`IMAGE_MIGRATION_LIMIT=10`と種別を指定してよい。全体dry-runのsummaryにある`last_attachment_id`を後続applyの`MAX_ATTACHMENT_ID`として固定する。

## 6. 範囲applyと再開

最初は十分小さい`LIMIT`で実行する。次は上限attachment IDを500、1回の件数を10とした例。

```bash
MIGRATION_REPORT_FILE="$MIGRATION_REPORT_DIR/apply-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

docker compose -f docker-compose.staging.yml run --rm \
  -e IMAGE_MIGRATION_APPLY=true \
  -e IMAGE_MIGRATION_CONFIRM=APPLY_LEGACY_IMAGE_PAIR_MIGRATION \
  -e IMAGE_MIGRATION_GIT_COMMIT="$MIGRATION_GIT_COMMIT" \
  -e IMAGE_MIGRATION_MAX_ATTACHMENT_ID=500 \
  -e IMAGE_MIGRATION_LIMIT=10 \
  app bin/rails image_attachments:migrate_legacy_pairs \
  > "$MIGRATION_REPORT_FILE"
```

summaryの`last_attachment_id`を次回の`IMAGE_MIGRATION_AFTER_ATTACHMENT_ID`へ指定する。`selected_count`が`LIMIT`未満になるまでレポートを分けて繰り返す。再実行時は完全な画像組だけが`skipped_migrated`となり、重複Blobを作らない。部分状態は自動修復しない。

個別再確認・再実行ではdry-runに記録された期待IDをすべて指定する。

```bash
docker compose -f docker-compose.staging.yml run --rm \
  -e IMAGE_MIGRATION_RECORD_TYPE=Store \
  -e IMAGE_MIGRATION_RECORD_ID=123 \
  -e IMAGE_MIGRATION_EXPECTED_ATTACHMENT_ID=456 \
  -e IMAGE_MIGRATION_EXPECTED_BLOB_ID=789 \
  -e IMAGE_MIGRATION_LIMIT=1 \
  app bin/rails image_attachments:migrate_legacy_pairs
```

applyする場合だけ、前述の`APPLY`、`CONFIRM`、`GIT_COMMIT`も追加する。期待ID不一致は`failed_conflict`となり、現在画像を上書きしない。

## 7. status

| status | 意味と対応 |
| --- | --- |
| `eligible` | dry-run検査成功。apply候補 |
| `migrated` | 1用途の移行成功 |
| `skipped_migrated` | 実体検査を含め完全な新方式画像組。変更なし |
| `skipped_no_legacy_source` | 新方式avatarへ更新済みでcover未設定。自動生成せず変更なし |
| `failed_partial_state` | source / display / crop dataの一部だけが存在、または内容不整合。個別確認 |
| `failed_blocked_by_cover` | User coverが未完了のため移行前avatarを維持 |
| `failed_blocked_by_avatar` | User avatarが部分状態のためcoverを生成しない |
| `failed_invalid_image` | 欠損、破損、未対応形式、容量・寸法・比率・処理上限 |
| `failed_upload` | 新規Blobの保存または存在確認失敗。生成済み一時Blobは清掃対象 |
| `failed_conflict` | dry-run後または処理中にattachment/blobが変更された。現在画像を維持 |
| `failed_save` | transactionまたはActive Record保存失敗 |
| `failed_record_missing` | 対象レコードが処理前に削除された |
| `failed_unexpected` | その他の失敗。error classを確認して実装Issueへ分離 |

失敗があっても別attachmentの処理は継続する。失敗statusを成功扱いに読み替えず、通常画面または個別Issueで解決してから再実行する。

## 8. apply後の照合

各段階で次を確認する。

- summaryの`selected_count`、`status_counts`、`last_attachment_id`
- `migrated`対象に編集元・表示用・crop dataが揃い、`sourceBlobId`が一致する
- Userのavatar用とcover用が別Blob・別キーである
- 表示用がavatar 1024×1024、その他1200×630のJPEGである
- 通常画面で再編集、差し替え、削除が成功する
- 公開カード、ヒーロー、待機画面、OGPが表示用画像を参照する
- workerが正常で、置換前Blobの`purge_later`が滞留していない
- 再dry-runで成功対象が`skipped_migrated`となり、新たな部分状態がない

## 9. 禁止事項

- #1162〜#1166の順序を飛ばさない
- dry-run結果と最大attachment IDを確認せずapplyしない
- `LIMIT`や確認文字列のguard（防御条件）をコード変更で迂回しない
- S3キーを直接上書きしない
- 部分状態、破損、競合を自動削除・強制上書きしない
- 移行と同時にFilePond、検証機能、S3 CORSを撤去しない
- 対象外の`DrinkItem.custom_icon`等を含めない
