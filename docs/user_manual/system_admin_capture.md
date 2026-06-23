# system_admin（運営）通常操作撮影

この文書は、第7回作業で取得した system_admin（運営）向け通常操作画面の撮影結果です。根拠は実コードの route（URL経路）/ Controller（処理）/ view（画面）/ Service（業務処理を集約するクラス）/ test（テスト）確認と、Playwright（ブラウザ自動操作）の実行結果です。

## 撮影コマンド

事前に固定撮影用データを作成します。

```bash
docker compose exec -T app bin/rails manual_capture:prepare
```

system_admin（運営）通常操作撮影を実行します。

```bash
npm run manual:capture:system_admin
```

今回の成功 run id（実行識別子）:

```text
20260623025629
```

## 使用した撮影用アカウント

| role（権限種別） | メールアドレス | 用途 |
| --- | --- | --- |
| `system_admin` | `manual+system_admin@example.test` | system_admin（運営）画面のログインと操作 |

共通パスワードは `docs/user_manual/manual_accounts.md` のローカル撮影用固定値を使用しました。読者向けマニュアル本文には固定パスワードを記載しません。

## 今回 UI から作成した撮影用データ

| 種別 | 値 | 実行結果 |
| --- | --- | --- |
| User（ユーザー） | `manual+system_admin_capture_user_20260623025629@example.test` | `/system_admin/users` に保存済み |
| ReferralCode（紹介コード） | `MANUAL-SYSTEM-ADMIN-20260623025629` | `/system_admin/referral_codes` に保存済み |
| Notification（お知らせ） | `マニュアル撮影用お知らせ 20260623025629` | `/system_admin/notifications` に保存済み |
| Effect（配信画面のエフェクト） | `manual_system_admin_20260623025629` | `/system_admin/effects` に保存済み |

これらは `manual` または `マニュアル撮影用` を含む development / test 専用の撮影識別子です。`MANUAL_CAPTURE_RUN_ID` を指定しない通常実行では、毎回一意の run id を使います。同じ run id を再利用すると uniqueness（一意制約）で失敗する可能性があります。

## 保存したスクリーンショット

### dashboard（ダッシュボード）

| ファイル | 対象 |
| --- | --- |
| `docs/user_manual/images/system_admin/dashboard/01_dashboard.png` | `/dashboard` system_admin（運営）カード一覧 |

### ユーザー管理

| ファイル | 対象 |
| --- | --- |
| `docs/user_manual/images/system_admin/users/01_index.png` | `/system_admin/users` ユーザー一覧 |
| `docs/user_manual/images/system_admin/users/02_new_form.png` | `/system_admin/users/new` ユーザー作成フォーム |
| `docs/user_manual/images/system_admin/users/03_filled.png` | ユーザー作成フォーム入力済み |
| `docs/user_manual/images/system_admin/users/04_after_save.png` | 保存後 `/system_admin/users` 一覧反映 |

### 紹介コード管理

| ファイル | 対象 |
| --- | --- |
| `docs/user_manual/images/system_admin/referral_codes/01_index.png` | `/system_admin/referral_codes` 紹介コード一覧 |
| `docs/user_manual/images/system_admin/referral_codes/02_new_form.png` | `/system_admin/referral_codes/new` 紹介コード作成フォーム |
| `docs/user_manual/images/system_admin/referral_codes/03_filled.png` | 紹介コード作成フォーム入力済み |
| `docs/user_manual/images/system_admin/referral_codes/04_after_save.png` | 保存後 `/system_admin/referral_codes` 一覧反映 |

### お知らせ管理

| ファイル | 対象 |
| --- | --- |
| `docs/user_manual/images/system_admin/notifications/01_index.png` | `/system_admin/notifications` お知らせ一覧 |
| `docs/user_manual/images/system_admin/notifications/02_new_form.png` | `/system_admin/notifications/new` お知らせ作成フォーム |
| `docs/user_manual/images/system_admin/notifications/03_filled.png` | お知らせ作成フォーム入力済み |
| `docs/user_manual/images/system_admin/notifications/04_after_save.png` | 保存後 `/system_admin/notifications` 一覧反映 |

### Effect 管理

| ファイル | 対象 |
| --- | --- |
| `docs/user_manual/images/system_admin/effects/01_index.png` | `/system_admin/effects` Effect 一覧 |
| `docs/user_manual/images/system_admin/effects/02_new_form.png` | `/system_admin/effects/new` Effect 作成フォーム |
| `docs/user_manual/images/system_admin/effects/03_filled.png` | Effect 作成フォーム入力済み |
| `docs/user_manual/images/system_admin/effects/04_after_save.png` | 保存後 `/system_admin/effects` 一覧反映 |

### 店舗選択 / 店舗BAN

| ファイル | 対象 |
| --- | --- |
| `docs/user_manual/images/system_admin/admin_stores/01_store_select.png` | `/admin/stores` 店舗選択画面 |
| `docs/user_manual/images/system_admin/admin_stores/02_after_store_select_dashboard.png` | `マニュアル撮影用店舗` 選択後 `/dashboard` |
| `docs/user_manual/images/system_admin/store_bans/01_index.png` | `/admin/store_bans` 店舗BAN一覧 / フォーム |
| `docs/user_manual/images/system_admin/store_bans/02_form_filled_not_submitted.png` | 店舗BANフォーム入力例。BAN作成は未実行 |

### 精算 / 振込 CSV / マニュアル精算

| ファイル | 対象 |
| --- | --- |
| `docs/user_manual/images/system_admin/settlements/01_index.png` | `/system_admin/settlements` 精算一覧 |
| `docs/user_manual/images/system_admin/settlement_exports/01_index.png` | `/system_admin/settlement_exports` 振込 CSV 一覧 |
| `docs/user_manual/images/system_admin/settlement_exports/02_show.png` | `/system_admin/settlement_exports/:id` 振込 CSV 詳細 |
| `docs/user_manual/images/system_admin/manual_settlements/01_manual_form.png` | `/system_admin/settlements/manual/new` マニュアル精算フォーム |
| `docs/user_manual/images/system_admin/manual_settlements/02_manual_filled.png` | マニュアル精算フォーム入力済み |
| `docs/user_manual/images/system_admin/manual_settlements/03_manual_preview.png` | preview（プレビュー）結果。確定は未実行 |

## 実際の遷移先

| 操作 | 遷移先 |
| --- | --- |
| `/admin/stores` で `マニュアル撮影用店舗` を選択 | `/dashboard` |
| ユーザー作成 | `/system_admin/users` |
| 紹介コード作成 | `/system_admin/referral_codes` |
| お知らせ作成 | `/system_admin/notifications` |
| Effect 作成 | `/system_admin/effects` |
| 店舗BANフォーム入力 | `/admin/store_bans` に留まる。送信なし |
| 精算一覧表示 | `/system_admin/settlements` |
| 振込 CSV 詳細表示 | `/system_admin/settlement_exports/:id` |
| マニュアル精算プレビュー | `/system_admin/settlements/manual/preview` 相当の POST 後に preview（プレビュー）表示 |

## 実行しなかった危険操作

- 自分自身の role（権限種別）変更。
- 最後の system_admin（運営）の降格。
- ユーザー停止 / 削除 / 復元に相当する操作。
- 紹介コードの無効化 / 有効化切り替え。
- お知らせの無効化 / 有効化切り替え。
- Effect の有効 / 無効切り替え。
- 店舗BAN作成、店舗BAN解除。
- 精算確定、支払済み更新。
- 振込 CSV 生成、CSV ダウンロード。
- マニュアル精算の確定作成。

## 外部サービス依存の扱い

- AWS / IVS（Amazon IVS の配信ルーム実体）は今回の撮影対象外です。system_admin 画面から IVS 作成・参加・配信開始は実行していません。
- Stripe（決済）は呼んでいません。振込 CSV 生成や決済完了撮影も未実行です。
- SMS（ショートメッセージ）は呼んでいません。
- Banuba / DeepAR（画面加工）は、Effect（配信画面のエフェクト）管理で文字列レコードを作成しただけです。zip ファイル実体アップロードやライセンス検証は行っていません。
- お知らせ作成は `SystemAdmin::NotificationsController` と `Notification` / `NotificationTag` の DB 保存のみ確認しました。外部通知やメール送信処理はこの作成経路では確認されませんでした。

## 未確認点

- `/system_admin/settlements` の詳細画面は、今回のデータ状態では一覧に安全に開ける settlement（精算）がなかったため未撮影です。
- `/system_admin/settlement_exports/:id` は既存の撮影用または開発用 export（書き出し）レコードがあったため詳細表示のみ撮影しました。CSV ダウンロードは未実行です。
- ユーザー停止、BAN解除、精算確定、支払済み更新、CSV生成は実行前の業務確認が必要です。
- system_admin（運営）の本番アカウント作成・付与手順は、自己登録ではなく運用手順として別途整理が必要です。
