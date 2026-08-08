# 表示用画像の棚卸し・是正手順

## 1. 目的

Store thumbnail、Booth thumbnail_image、User avatarに保存済みのHEIC / HEIFや、メタデータと実体が一致しない画像をActive Storage経由で安全に是正する。

最初にdry-run（変更なし）で棚卸しし、対象を確認した後、1件ずつ明示的にJPEGへ再添付する。S3キーへ変換後のバイト列を直接上書きしない。

## 2. 対象候補

標準の棚卸しでは、対象の表示用添付から次のDBメタデータに一致する候補だけを実体検査する。

- content_typeが`image/heic`、`image/heif`、`application/octet-stream`
- filenameの拡張子が`.heic`または`.heif`（大文字小文字を区別しない）

候補ごとに保存先オブジェクトの存在、ImageMagickが判定した実体形式、`ImageAttachments::NormalizeService`によるJPEG変換可否を確認する。

## 3. 実行前確認

対象環境へ反映されたcommitとコンテナのHEIC対応を確認する。

```bash
git log -1 --oneline
docker compose -f docker-compose.production.yml exec -T app \
  identify -list format | grep -E 'HEIC|HEIF'
```

使用するcomposeファイル名とenv-file指定は対象環境の既存デプロイ手順に合わせる。

## 4. 標準dry-run

最初はDBメタデータ候補だけを検査し、JSON Lines形式の結果をファイルへ保存する。

```bash
docker compose -f docker-compose.production.yml exec -T app \
  bin/rails image_attachments:inventory \
  | tee image-attachment-inventory-$(date +%Y%m%d-%H%M%S).jsonl
```

先頭行は件数のsummary、それ以降は添付ごとの結果である。すべての行に`dry_run: true`が入る。
検査中のActive Storage内部ログは抑制し、S3キーはレポートへ出力しない。filenameは利用者入力を含む可能性があるため、保存したレポートは運用担当者だけが参照できる場所で管理する。

主なstatus:

- `needs_normalization`: JPEG以外の対応画像で、JPEGへ変換可能
- `metadata_mismatch`: 実体はJPEGだがfilenameまたはcontent_typeがJPEGと一致しない
- `missing`: 保存先オブジェクトが存在しない
- `unreadable`: ImageMagickが実体を読み取れない
- `conversion_failed`: 実体形式は読めるがJPEG正規化に失敗
- `inspection_failed`: 保存先アクセスなど、その他の検査失敗
- `ok`: 全件実体検査時に、実体とメタデータが正しいJPEG

## 5. 対象を限定したdry-run

record_typeとrecord_idを指定して、既知の1レコードだけを再確認できる。

```bash
docker compose -f docker-compose.production.yml exec -T \
  -e IMAGE_INVENTORY_RECORD_TYPE=Store \
  -e IMAGE_INVENTORY_RECORD_ID=1 \
  app bin/rails image_attachments:inventory
```

`IMAGE_INVENTORY_RECORD_TYPE`は`Store`、`Booth`、`User`だけを許可する。record_idだけの指定は、別record_typeの同じIDを誤って対象にしないため拒否する。

## 6. 全件実体検査

DBメタデータがJPEGを示す画像も含めた全件検査はS3ダウンロードと画像変換を伴うため、`IMAGE_INVENTORY_LIMIT`を必須とする。最初は少数で実行する。

```bash
docker compose -f docker-compose.production.yml exec -T \
  -e IMAGE_INVENTORY_INSPECT_ALL=true \
  -e IMAGE_INVENTORY_LIMIT=10 \
  app bin/rails image_attachments:inventory
```

このlimitは添付ID順の先頭から適用される。全件を一度に検査する用途には使わない。
summaryの`last_attachment_id`を次回の`IMAGE_INVENTORY_AFTER_ATTACHMENT_ID`へ指定すると、次のバッチを検査できる。`inspected_count`がlimit未満になるまで、結果ファイルを分けて繰り返す。

```bash
docker compose -f docker-compose.production.yml exec -T \
  -e IMAGE_INVENTORY_INSPECT_ALL=true \
  -e IMAGE_INVENTORY_LIMIT=10 \
  -e IMAGE_INVENTORY_AFTER_ATTACHMENT_ID=123 \
  app bin/rails image_attachments:inventory
```

## 7. 1件を指定した補正dry-run

棚卸し結果のrecord、attachment、blobをすべて指定する。既定では再検査だけを行い、添付を変更しない。

```bash
docker compose -f docker-compose.production.yml run --rm \
  -e IMAGE_REMEDIATION_RECORD_TYPE=Store \
  -e IMAGE_REMEDIATION_RECORD_ID=123 \
  -e IMAGE_REMEDIATION_ATTACHMENT_NAME=thumbnail \
  -e IMAGE_REMEDIATION_EXPECTED_ATTACHMENT_ID=456 \
  -e IMAGE_REMEDIATION_EXPECTED_BLOB_ID=789 \
  app bin/rails image_attachments:remediate
```

`status`が`eligible`であることと、出力されたattachment ID・blob IDが保存済みの棚卸し結果と一致することを確認する。この段階では`dry_run: true`であり、Blob、Attachment、対象Record、S3オブジェクトを変更しない。

## 8. 1件を指定した補正apply

dry-runと同じ5項目を指定し、`APPLY=true`と確認値を追加する。確認値は`record_type:record_id:attachment_name:attachment_id:blob_id`の順に連結する。

```bash
docker compose -f docker-compose.production.yml run --rm \
  -e IMAGE_REMEDIATION_RECORD_TYPE=Store \
  -e IMAGE_REMEDIATION_RECORD_ID=123 \
  -e IMAGE_REMEDIATION_ATTACHMENT_NAME=thumbnail \
  -e IMAGE_REMEDIATION_EXPECTED_ATTACHMENT_ID=456 \
  -e IMAGE_REMEDIATION_EXPECTED_BLOB_ID=789 \
  -e IMAGE_REMEDIATION_APPLY=true \
  -e IMAGE_REMEDIATION_CONFIRM=Store:123:thumbnail:456:789 \
  app bin/rails image_attachments:remediate
```

補正処理は次の順序で行う。

1. 現在のrecord、attachment、blobが指定値と一致することを確認する
2. 保存先の実体形式とJPEG変換可否を再検査する
3. `ImageAttachments::UpdateService`でJPEGを新規Blobとしてアップロードし、保存先に存在することを確認する
4. recordをロックし、attachment ID・blob IDを再照合してから新Blobを添付する
5. 添付後の実体とメタデータが正常なJPEGであることを確認する
6. transaction完了後に旧Blobの`purge_later`を登録する

棚卸し後に対象添付が変更されていた場合は`StaleTargetError`で停止し、新しい添付を上書きしない。すでに正常なJPEGへ補正済みの場合は`skipped_already_normalized`となり、二重変換しない。成功時は`normalized`、失敗時は`failed`をJSONで出力する。
補正中もActive Storage内部ログを抑止し、JSON結果へS3キーを出力しない。filenameは利用者入力を含む可能性があるため、結果ファイルは棚卸しレポートと同様に管理する。

## 9. apply後の確認

全件検査を対象recordの1件に限定し、新しい添付が`ok`であることを確認する。

```bash
docker compose -f docker-compose.production.yml run --rm \
  -e IMAGE_INVENTORY_INSPECT_ALL=true \
  -e IMAGE_INVENTORY_LIMIT=1 \
  -e IMAGE_INVENTORY_RECORD_TYPE=Store \
  -e IMAGE_INVENTORY_RECORD_ID=123 \
  app bin/rails image_attachments:inventory
```

続いて対象画面を主要ブラウザで確認する。旧Blobの削除は非同期job（バックグラウンド処理）のため、workerが正常稼働していることも確認する。

## 10. 禁止事項

- S3キーへJPEGバイト列を直接上書きしない
- dry-run結果の確認前にapplyしない
- 孤児Blobや対象外添付を同時に削除しない
- `missing`、`unreadable`、`conversion_failed`を自動的に削除しない
- attachment ID・blob IDの一致エラーを無視して強制更新しない
