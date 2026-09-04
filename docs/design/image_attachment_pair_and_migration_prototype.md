# 編集元・表示用の一体更新と既存画像移行の試作（#1133）

> 本書はローカルDiskでの試作記録であり、実行可能な移行batchやステージング移行の完了記録ではない。編集元上限、保存名、multipart契約、段階的な環境実行は#1134で確定した [Cropper.js画像アップロード確定設計](image_upload_cropper_architecture.md) と [実装計画](image_upload_implementation_plan.md) を優先する。

## 範囲と結論

本Issueは、本番モデルへ添付・カラムを追加せず、将来の画像更新Service（業務処理を集約するクラス）と一回限りの移行処理の境界を試作する。FilePond、本番フォーム、保存済み画像、本番・ステージングS3は変更しない。

採用候補は次の構成とする。

1. Controller（リクエストを受ける層）は2枚のJPEG・クロップ情報・編集開始時の期待IDを受け、認可と形式検査を行う。
2. 新規画像は編集元JPEGと表示用JPEGを事前に別Blobへ保存し、保存先に存在することを確認する。
3. `ImageAttachments::StagedPairUpdateService` がレコードをロックし、期待するsource/displayのattachment ID・blob IDを照合する。同じDB transaction（データベースの一連処理）で2添付とクロップ情報を更新する。
4. transaction失敗・競合時は旧状態を維持して新規Blobだけを同期清掃する。成功時だけ参照されなくなった旧Blobを非同期清掃する。他レコードにも添付されたBlobは削除しない。
5. 既存画像移行は `ImageAttachments::LegacyPairBuilder` が現在の表示Blobを一時ファイルへ開き、独立キーの編集元JPEG、中央クロップした表示用JPEG、初期クロップ情報を生成する。生成物の確定は同じ一体更新Serviceへ渡す。

`ImageAttachments::UpdateService` は、従来フォームの「入力画像をサーバーで正規化して単一添付を更新する」責務を維持する。新方式ではブラウザが生成した検査済みJPEGを再圧縮せず2添付として確定するため、既存Serviceへ条件分岐を増やさない。共通化は本番実装後に実処理の重複が明確になった範囲だけで行う。

## 用途と将来の保存先候補

| 対象 | 既存表示 | 新しい編集元候補 | 表示用 | 比率・出力 |
| --- | --- | --- | --- | --- |
| Userアバター | `avatar` | `avatar_source` | `avatar` | 1:1、1024×1024 |
| Userヒーロー・カード | 移行時は既存`avatar`を使用 | `cover_image_source` | 新規`cover_image`候補 | 40:21、1200×630 |
| Store | `thumbnail` | `thumbnail_source` | `thumbnail` | 40:21、1200×630 |
| Booth | `thumbnail_image` | `thumbnail_image_source` | `thumbnail_image` | 40:21、1200×630 |

最終命名は`cover_image_source` / `cover_image` / `cover_image_crop_data`とし、Userカード・プロフィールヒーロー・OGPで共有する。本試作自体はsquare/socialという用途キーでモデル名に依存しない。

## 一体更新の契約

`StagedPairUpdateService` は、内容検査・所有者確認を通過した未添付Blobだけを受け取る。次の二つを区別する。

- 再編集: `new_source_blob`を渡さず、既存sourceを保持する。新しいdisplayとcrop dataだけを更新する。
- 新画像への差し替え・移行: 新しいsourceとdisplayを両方渡し、crop dataも更新する。

編集画面表示時にsource/displayのattachment ID・blob IDを `Snapshot` として取得する。保存時はレコードロックと添付行ロックの下で4値を再照合し、一つでも変わっていれば `StalePairError` とする。これにより、古いタブや移行棚卸し後に変更された画像による上書きを拒否する。

クロップ情報はクライアントの `schemaVersion: 1` を基にし、保存直前にServiceが実際に確定するsource Blob IDを `sourceBlobId`へ上書きする。再読込時は次をすべて満たす場合だけ復元する。

- crop dataのschema version・用途・出力設定が対応済み
- `sourceBlobId`が現在のsource Blob IDと一致
- 保存寸法が読み込んだsourceの実寸法と一致
- crop範囲・比率・zoomが再検証を通る

一致しない場合、別画像の座標を適用せず再クロップを要求する。クライアント値だけでBlobの関連を決めない。

## 既存画像からの生成

`LegacyPairBuilder` は `blob.download` で全体をRuby文字列へ展開せず、`blob.open`の一時ファイルをImageMagickへ渡す。生成Blobは元Blob・別用途・source/display間で必ず別ID・別キーとなる。

- JPEGかつ向きが`Undefined` / `TopLeft`で、用途の最低寸法を満たす場合は、編集元を再圧縮せずストリームコピーする。
- それ以外は先頭画像を向き補正し、白背景・sRGB・メタデータ除去・品質0.94のJPEGへ変換する。
- 小さい画像は全体を残したまま、squareでは1024×1024以上、socialでは1200×630以上になる最小倍率で拡大する。細部は増えないが、今ある画像を初回の編集元として扱える。
- 中央から最大の1:1または40:21整数領域を取得し、品質0.90で1024×1024または1200×630へ出力する。
- source blob ID、変換後source寸法、元画像座標、zoom、出力設定を初期crop dataへ保存する。

48×32の入力による試作結果は次のとおり。

| 用途 | 編集元 | 中央クロップ | 表示用 |
| --- | --- | --- | --- |
| square | 1536×1024 | x=256, y=0, 1024×1024, zoom=1.5 | 1024×1024 |
| social | 1200×800 | x=0, y=85, 1200×630, zoom=1.0 | 1200×630 |

1600×900の正常向きJPEGは縮小・再圧縮せず独立Blobへコピーし、1600×840（x=0, y=30）を中央クロップした。dry-runは同じデコード・変換・出力検査まで行うが、Blobを作らない。

## 失敗時と競合時

| 失敗点 | 結果 |
| --- | --- |
| 元Blob欠損・破損・非対応・処理上限 | 生成Blobなしで失敗 |
| source生成後にdisplay生成・アップロード失敗 | 生成済みの新規Blobだけ同期削除 |
| 事前アップロード済みBlobが保存先にない | transaction開始前に拒否し、他の新規Blobも清掃 |
| 期待attachment/blob ID不一致 | 旧または同時更新後の状態を維持し、新規Blobを清掃 |
| レコード検証・関連更新・明示rollback | 添付とcrop dataをまとめてrollbackし、新規Blobを清掃 |
| commit後の旧Blob清掃登録失敗 | 新状態は維持して記録し、旧Blob清掃を再試行対象にする |
| 旧Blobが別レコードにも添付済み | 旧Blobを削除しない |

`ActiveRecord::Rollback` はtransaction API内で呼出元へ再送出されないため、transaction末尾へ到達した印を確認する。明示rollbackを成功と誤認して新規Blobを残さない。

DBとS3を一つのtransactionにはできない。したがって「事前アップロード→存在・内容確認→短いDB transaction→旧Blob清掃」を採る。プロセス強制終了で同期清掃まで到達しない場合に備え、本番実装ではステージングBlobに期限と所有者を記録する清掃経路も必要になる。

## 一回限りの移行方式

本番カラム追加後、既存 `InventoryService` のattachment IDカーソルを再利用して、用途単位で1件ずつ処理する。

1. dry-runで対象総数、画像なし、保存先欠損、破損・非対応、拡大対象を集計する。
2. `record_type`、`record_id`、既存attachment ID・blob ID、用途、入力寸法、判定だけをJSON Linesへ記録する。S3キー、署名URL、画像、個人情報は出さない。
3. applyでは棚卸し時のattachment/blob IDを期待値にして再照合する。Userの2用途は同じ既存avatarを先に開いて両用途の生成を済ませてから確定処理へ進む。
4. source/display/crop dataがすべて揃い、`sourceBlobId`と用途・寸法が一致するものだけを `skipped_already_migrated` とする。部分状態は成功扱いにしない。
5. 1用途ごとにcommitし、最後に処理したattachment IDを記録する。中断後は `after_attachment_id`または明示ID範囲から再開する。スキップ判定を再実行するため重複更新しない。

状態は `eligible`、`would_enlarge`、`migrated`、`skipped_already_migrated`、`skipped_no_image`、`failed_missing`、`failed_unreadable`、`failed_stale`、`failed_upload`、`failed_save` とする。失敗一覧は再入力に使える期待IDを保持し、画像が変わった対象を無理に再実行しない。

実行順は、Userのヒーロー・カード用を既存avatarから生成した後にアバター用を確定するか、2用途を事前生成してから順に確定する。アバターを先に置き換えて、その中央クロップ後画像をヒーロー用の元にしない。

## 送信方式の扱い

#1132のiPhone実測では、同一の約3.96MB・square画像でmultipartが全体4083ms、directが1859msだった。両方式ともsource/displayのSHA-256は一致した。一方、当面の同時接続数は少なく、運用と失敗状態が単純なRails経由をユーザーが有力と考えている。

本試作の一体更新Serviceは送信方式に依存しない。#1134でRails multipartを初期方式、source 20MiB・display 5MiB・全体26MiB・クライアント待ち45秒とした。利用増加や実測に応じてdirectへ切り替えられる境界は維持する。将来directを採る場合は、書換可能な署名URLの一時キーから検査済み確定キーへ複製したBlobだけを本Serviceへ渡す。

## 自動確認結果と後続Issue

2026-09-04、Diskサービスを使い、既存 `UpdateService` / `InventoryService` / `RemediateService` を含む関連39件・215 assertionsが成功した。新規試作では、物理的に独立したBlob、拡大、上限を超える拡大の拒否、非縮小・JPEGバイト維持、2比率の中央クロップ、dry-run、再編集、全差し替え、表示用アップロード途中失敗、明示rollback、関連レコード失敗、競合、保存先欠損、無効crop、共有Blob保護を確認した。RuboCopは全550ファイルで指摘なし、Brakemanはエラー・セキュリティ警告ともに0件だった。

本番実装Issueには最低限、次の自動テストを含める。

- User / Store / Boothそれぞれの新規・再編集・差し替え・削除方針
- crop dataとsource Blob ID・実寸法の復元照合
- 2画像の片方失敗、DB validation、関連更新失敗、明示rollback、競合更新
- commit前の新規Blob清掃、commit後の旧Blob清掃、共有Blob保護、強制終了後の期限清掃
- dry-run件数、拡大・欠損・破損分類、ID範囲、途中再開、再実行スキップ
- Userの既存avatarから2用途を作る際に同じ移行元を使うこと

#1134で、Userカバー添付名、用途単位でsourceも削除する契約、multipart全体26MiB、crop schema version 1、移行ログの本番完了後90日保持を確定した。モデル追加、フォーム移行、移行batch、環境別実行、FilePond撤去は#1140〜#1145へ分割した。
