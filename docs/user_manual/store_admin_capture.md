# 第4回 store_admin 通常操作画面撮影記録

この文書は、store_admin（店舗管理者）向けの通常操作画面を Playwright（ブラウザ自動操作）で撮影した記録です。撮影は development（開発環境）で実施し、production（本番環境）向けの挙動は変更していません。

## 撮影コマンド

```bash
docker compose exec -T app bin/rails manual_capture:prepare
npm run manual:capture:store_admin
```

今回成功した実行 ID は `20260623004735` です。store_admin（店舗管理者）は `manual_capture:prepare` が作成する `manual+store_admin@example.test` を使用しました。

## 撮影した画面と実際の遷移先

| 対象 | 開始 URL | 実際の遷移・結果 |
| --- | --- | --- |
| dashboard（ダッシュボード） | `/dashboard` | store_admin（店舗管理者）向けカード一覧を表示 |
| 店舗選択 | `/admin/stores` | `マニュアル撮影用店舗` と `マニュアル撮影用サブ店舗` を表示 |
| 店舗情報編集 | dashboard の「店舗設定編集」 | `/admin/stores/:id/edit` → 更新後 `/dashboard` |
| ブース管理 | `/admin/booths` | 一覧表示、`/admin/booths/new` で作成、作成後 `/dashboard`、再度 `/admin/booths` で反映確認 |
| キャスト一覧 | `/admin/casts` | 所属中 cast（配信者）を表示 |
| キャスト招待 | `/admin/cast_invitations` | 招待 URL 発行後、同画面で一覧表示 |
| 店舗管理者招待 | `/admin/store_admin_invitations` | 招待 URL 発行後、同画面で一覧表示 |
| ドリンクメニュー管理 | `/admin/drink_items` | 新規ドリンク作成後、同画面で一覧反映 |
| 配信者別数値一覧 | `/admin/cast_metrics` | 初期表示と `?all_casts=1` の表示を撮影 |
| 通報一覧 | `/admin/comment_reports` | 通報がない状態を撮影 |
| 振込先口座設定 | `/admin/payout_account/edit` | ダミー口座を入力し、更新後も同画面を表示 |
| 精算（予定・履歴） | `/admin/settlements` | 精算予定と履歴の空状態を撮影 |

## 保存したスクリーンショット

### dashboard（ダッシュボード）

- `images/store_admin/dashboard/01_dashboard.png`

### 店舗選択・店舗情報編集

- `images/store_admin/stores/01_index.png`
- `images/store_admin/stores/02_edit_form.png`
- `images/store_admin/stores/03_edit_filled.png`
- `images/store_admin/stores/04_after_update_dashboard.png`

### ブース管理

- `images/store_admin/booths/01_index.png`
- `images/store_admin/booths/02_new_form.png`
- `images/store_admin/booths/03_new_filled.png`
- `images/store_admin/booths/04_after_create_dashboard.png`
- `images/store_admin/booths/05_index_after_create.png`

### キャスト一覧

- `images/store_admin/casts/01_index.png`

### 招待管理

- `images/store_admin/invitations/01_cast_invitation_index.png`
- `images/store_admin/invitations/02_cast_invitation_filled.png`
- `images/store_admin/invitations/03_cast_invitation_issued.png`
- `images/store_admin/invitations/04_store_admin_invitation_index.png`
- `images/store_admin/invitations/05_store_admin_invitation_issued.png`

### ドリンクメニュー管理

- `images/store_admin/drink_items/01_index.png`
- `images/store_admin/drink_items/02_new_filled.png`
- `images/store_admin/drink_items/03_after_create.png`

### 数値・通報・精算関連

- `images/store_admin/metrics/01_index.png`
- `images/store_admin/metrics/02_all_casts.png`
- `images/store_admin/comment_reports/01_index.png`
- `images/store_admin/payout_account/01_edit_form.png`
- `images/store_admin/payout_account/02_edit_filled.png`
- `images/store_admin/payout_account/03_after_update.png`
- `images/store_admin/settlements/01_index.png`

## 実行しなかった危険操作

- cast（配信者）の所属解除。
- Booth（ブース）の閉鎖・アーカイブ。
- 配信の強制終了。
- 通報の却下、BAN、BAN解除。
- settlement（精算）の確定、支払処理、振込 CSV 出力。
- Stripe（決済）、SMS（ショートメッセージ）、Banuba / DeepAR（画面加工）に関わる操作。

## 外部サービス依存の回避

ブース作成時は `Booths::ProvisionIvsStageService` が呼ばれます。第3回で追加した方針により、production（本番環境）以外で、店舗名に `manual` または `マニュアル撮影用` を含むマニュアル撮影用店舗だけ、AWS（Amazon Web Services）を呼ばずに疑似 `ivs_stage_arn` を保存します。

今回作成したブースも `マニュアル撮影用店舗` 配下のため、IVS Stage（Amazon IVS の配信ルーム実体）は疑似 ARN で処理されています。

振込先口座設定では、実銀行口座情報ではなく `0001` / `001` / `1234567` / `マニュアルサツエイヨウ` のダミー値だけを使用しました。

## 確認した主な実コード

- `config/routes.rb`
- `app/controllers/dashboard_controller.rb`
- `app/views/dashboard/show.html.erb`
- `app/controllers/admin/base_controller.rb`
- `app/controllers/admin/stores_controller.rb`
- `app/controllers/admin/current_stores_controller.rb`
- `app/controllers/admin/booths_controller.rb`
- `app/controllers/admin/casts_controller.rb`
- `app/controllers/admin/cast_invitations_controller.rb`
- `app/controllers/admin/store_admin_invitations_controller.rb`
- `app/controllers/admin/drink_items_controller.rb`
- `app/controllers/admin/metrics_controller.rb`
- `app/controllers/admin/comment_reports_controller.rb`
- `app/controllers/admin/store_payout_accounts_controller.rb`
- `app/controllers/admin/settlements_controller.rb`
- `app/services/booths/provision_ivs_stage_service.rb`
- `test/lib/tasks/manual_capture_task_test.rb`
- `test/integration/admin_booths_index_test.rb`
- `test/integration/admin/booth_create_with_cast_assignment_test.rb`
- `test/integration/admin_store_payout_account_test.rb`

## 未確認点

- mobile（スマートフォン幅）の store_admin（店舗管理者）画面は未撮影です。
- 通報がある状態、精算履歴がある状態、配信者別数値に売上がある状態は未撮影です。
- ブース作成時のサムネイルアップロードは未撮影です。
- ドリンク編集フォームは、今回は新規作成フォームで代替し、既存ドリンクの編集保存までは撮影していません。
- 招待 URL の期限切れ・使用済み状態は未撮影です。
