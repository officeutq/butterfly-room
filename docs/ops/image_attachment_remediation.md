# 表示用画像の棚卸し・是正手順

## 1. 目的

Store thumbnail、Booth thumbnail_image、User avatarに保存済みのHEIC / HEIFや、メタデータと実体が一致しない画像をActive Storage経由で安全に是正する。

この手順の第1段階はdry-run（変更なし）の棚卸しだけを行う。S3オブジェクト、Active StorageのBlob・Attachment、Store / Booth / Userは更新・削除しない。

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

## 7. 禁止事項と次段階

- S3キーへJPEGバイト列を直接上書きしない
- dry-run結果の確認前に旧Blobをpurgeしない
- 孤児Blobや対象外添付を同時に削除しない
- `missing`、`unreadable`、`conversion_failed`を自動的に削除しない

実際の再添付は、dry-run結果を保存・確認した後に別の明示的なapply手順として実装する。新JPEGのアップロードと添付成功を確認してから旧Blobをpurgeし、1件単位で再実行可能にする。
