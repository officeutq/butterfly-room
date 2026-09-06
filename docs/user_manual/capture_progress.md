# 撮影進捗

この文書は、操作マニュアル用スクリーンショット取得の進捗メモです。

## 第2回で取得済みの smoke（最小確認）スクリーンショット

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/smoke/guest_home.png` | guest（未ログイン）ホーム | 取得済み |
| `docs/user_manual/images/smoke/login.png` | ログイン画面 | 取得済み |
| `docs/user_manual/images/smoke/customer_dashboard.png` | customer（視聴者）ログイン後 `/dashboard` | 取得済み |
| `docs/user_manual/images/smoke/store_admin_dashboard.png` | store_admin（店舗管理者）ログイン後 `/dashboard` | 取得済み |
| `docs/user_manual/images/smoke/cast_dashboard.png` | cast（配信者）ログイン後 `/dashboard` | 取得済み |
| `docs/user_manual/images/smoke/system_admin_dashboard.png` | system_admin（運営）ログイン後 `/dashboard` | 取得済み |

## 第3回で取得済みのアカウント作成スクリーンショット

### customer（視聴者）自己登録

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/account_creation/customer/01_signup_form.png` | `/sign_up` 登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/customer/02_signup_filled.png` | 入力済み登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/customer/03_after_signup_profile_edit.png` | 登録後 `/profile/edit` | 取得済み |

### store_admin（店舗管理者）店舗登録

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/account_creation/store_admin_registration/01_registration_form.png` | `/stores/new_registration?ref=...` 登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_registration/02_registration_filled.png` | 入力済み登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_registration/03_after_registration_store_edit.png` | 旧フローの登録後 `/admin/stores/:id/edit` | 参照停止・次回撮影時に削除 |
| `docs/user_manual/images/account_creation/store_admin_registration/03_after_registration_initial_setup.png` | 登録後の初回店舗設定 | 要再撮影（spec更新済み） |
| `docs/user_manual/images/account_creation/store_admin_registration/04_after_initial_setup_thanks.png` | 保存・公開後の登録完了 | 要再撮影（spec更新済み） |
| `docs/user_manual/images/account_creation/store_admin_registration/05_after_registration_dashboard.png` | 完了後のダッシュボード | 要再撮影（spec更新済み） |

### cast（配信者）招待登録

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/account_creation/cast_invitation/01_admin_invitation_form.png` | store_admin（店舗管理者）で cast invitation（配信者招待）発行フォーム | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/02_admin_invitation_filled.png` | 招待メモ入力済み | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/03_admin_invitation_issued.png` | 招待 URL 発行後 | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/04_invitation_guest.png` | 未ログインで招待 URL を開いた画面 | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/05_signup_form.png` | `/cast/sign_up?token=...` 登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/06_signup_filled.png` | 入力済み登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/07_after_signup_invitation.png` | 登録後の招待確認画面 | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/08_after_accept_profile_edit.png` | 招待承認後 `/profile/edit` | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/09_profile_filled.png` | プロフィール入力済み | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/10_after_profile_booth_edit.png` | プロフィール更新後 `/cast/booths/:id/edit` | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/11_booth_filled.png` | ブース編集入力済み | 取得済み |
| `docs/user_manual/images/account_creation/cast_invitation/12_after_booth_update_home.png` | ブース更新後 `/` | 取得済み |

### 追加 store_admin（店舗管理者）招待登録

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/account_creation/store_admin_invitation/01_admin_invitation_form.png` | store_admin invitation（店舗管理者招待）発行画面 | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_invitation/02_admin_invitation_issued.png` | 招待 URL 発行後 | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_invitation/03_invitation_guest.png` | 未ログインで招待 URL を開いた画面 | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_invitation/04_signup_form.png` | `/store_admin/sign_up?token=...` 登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_invitation/05_signup_filled.png` | 入力済み登録フォーム | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_invitation/06_after_signup_invitation.png` | 登録後の招待確認画面 | 取得済み |
| `docs/user_manual/images/account_creation/store_admin_invitation/07_after_accept_dashboard.png` | 招待承認後 `/dashboard` | 取得済み |

## 第3回時点で取得できなかったもの

- mobile（スマートフォン幅）でのアカウント作成フロー。
- 招待 URL の期限切れ / 使用済み / role（権限種別）違いのエラー画面。
- SMS OTP（ショートメッセージのワンタイム認証コード）入力フロー。
- Stripe（決済）完了フロー。
- cast（配信者）の配信開始から終了までの完全フロー。

## 第4回で取得済みの store_admin（店舗管理者）通常操作スクリーンショット

### dashboard（ダッシュボード）

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/store_admin/dashboard/01_dashboard.png` | `/dashboard` store_admin（店舗管理者）カード一覧 | 取得済み |

### 店舗選択・店舗情報編集

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/store_admin/stores/01_index.png` | `/admin/stores` 店舗選択 | 取得済み |
| `docs/user_manual/images/store_admin/stores/02_edit_form.png` | `/admin/stores/:id/edit` 店舗設定編集フォーム | 取得済み |
| `docs/user_manual/images/store_admin/stores/03_edit_filled.png` | 店舗設定編集フォーム入力済み | 取得済み |
| `docs/user_manual/images/store_admin/stores/04_after_update_dashboard.png` | 店舗情報更新後 `/dashboard` | 取得済み |

### ブース管理・キャスト管理

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/store_admin/booths/01_index.png` | `/admin/booths` ブース管理一覧 | 取得済み |
| `docs/user_manual/images/store_admin/booths/02_new_form.png` | `/admin/booths/new` ブース作成フォーム | 取得済み |
| `docs/user_manual/images/store_admin/booths/03_new_filled.png` | ブース作成フォーム入力済み | 取得済み |
| `docs/user_manual/images/store_admin/booths/04_after_create_dashboard.png` | ブース作成後 `/dashboard` | 取得済み |
| `docs/user_manual/images/store_admin/booths/05_index_after_create.png` | 作成後 `/admin/booths` 一覧反映 | 取得済み |
| `docs/user_manual/images/store_admin/casts/01_index.png` | `/admin/casts` キャスト一覧 | 取得済み |

### 招待管理・ドリンクメニュー

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/store_admin/invitations/01_cast_invitation_index.png` | `/admin/cast_invitations` キャスト招待一覧 / 発行画面 | 取得済み |
| `docs/user_manual/images/store_admin/invitations/02_cast_invitation_filled.png` | キャスト招待メモ入力済み | 取得済み |
| `docs/user_manual/images/store_admin/invitations/03_cast_invitation_issued.png` | キャスト招待 URL 発行後 | 取得済み |
| `docs/user_manual/images/store_admin/invitations/04_store_admin_invitation_index.png` | `/admin/store_admin_invitations` 店舗管理者招待画面 | 取得済み |
| `docs/user_manual/images/store_admin/invitations/05_store_admin_invitation_issued.png` | 店舗管理者招待 URL 発行後 | 取得済み |
| `docs/user_manual/images/store_admin/drink_items/01_index.png` | `/admin/drink_items` ドリンク一覧 / 新規作成フォーム | 取得済み |
| `docs/user_manual/images/store_admin/drink_items/02_new_filled.png` | ドリンク新規作成フォーム入力済み | 取得済み |
| `docs/user_manual/images/store_admin/drink_items/03_after_create.png` | ドリンク作成後の一覧反映 | 取得済み |

### 数値・通報・口座・精算

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/store_admin/metrics/01_index.png` | `/admin/cast_metrics` 配信者別数値一覧 | 取得済み |
| `docs/user_manual/images/store_admin/metrics/02_all_casts.png` | `/admin/cast_metrics?all_casts=1` 全キャスト表示 | 取得済み |
| `docs/user_manual/images/store_admin/comment_reports/01_index.png` | `/admin/comment_reports` 通報一覧 | 取得済み |
| `docs/user_manual/images/store_admin/payout_account/01_edit_form.png` | `/admin/payout_account/edit` 振込先口座設定フォーム | 取得済み |
| `docs/user_manual/images/store_admin/payout_account/02_edit_filled.png` | 振込先口座設定フォーム入力済み | 取得済み |
| `docs/user_manual/images/store_admin/payout_account/03_after_update.png` | 振込先口座更新後 | 取得済み |
| `docs/user_manual/images/store_admin/settlements/01_index.png` | `/admin/settlements` 精算（予定・履歴） | 取得済み |

## 第5回で取得済みの cast（配信者）通常操作スクリーンショット

### dashboard（ダッシュボード）

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/cast/dashboard/01_dashboard.png` | `/dashboard` cast（配信者）カード一覧 | 取得済み |

### ブース一覧・ブース情報

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/cast/booths/01_index.png` | `/cast/booths` ブース一覧 | 取得済み |
| `docs/user_manual/images/cast/booths/02_show.png` | `/cast/booths/:id` ブース情報 | 取得済み |
| `docs/user_manual/images/cast/booths/03_index_current_booth.png` | `/cast/booths` current booth（現在選択中のブース）表示 | 取得済み |

### ブース編集

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/cast/booth_edit/01_edit_form.png` | `/cast/booths/:id/edit` ブース編集フォーム | 取得済み |
| `docs/user_manual/images/cast/booth_edit/02_edit_filled.png` | ブース編集フォーム入力済み | 取得済み |
| `docs/user_manual/images/cast/booth_edit/03_after_update_dashboard.png` | ブース更新後 `/dashboard` | 取得済み |

### 配信画面・配信履歴・ドリンク消化関連

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/cast/live/01_live_standby_initial.png` | `/booths/:id/enter` 後の `/cast/booths/:id/live` standby（配信準備中）画面 | 取得済み |
| `docs/user_manual/images/cast/stream_sessions/01_index_empty.png` | `/cast/booths/:booth_id/stream_sessions` 配信履歴の空状態 | 取得済み |
| `docs/user_manual/images/cast/drink_orders/01_pending_empty.png` | `/cast/stream_sessions/:id/pending_drink_orders` pending drink orders（未消化ドリンク）の空状態 | 取得済み |

## 第6回で取得済みの customer（視聴者）通常操作スクリーンショット

### dashboard（ダッシュボード）・プロフィール・電話番号

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/customer/dashboard/01_dashboard.png` | `/dashboard` customer（視聴者）カード一覧 | 取得済み |
| `docs/user_manual/images/customer/profile/01_edit_form.png` | `/profile/edit` プロフィール編集フォーム | 取得済み |
| `docs/user_manual/images/customer/profile/02_edit_filled.png` | プロフィール編集フォーム入力済み | 取得済み |
| `docs/user_manual/images/customer/profile/03_after_update_home.png` | プロフィール更新後 `/` | 取得済み |
| `docs/user_manual/images/customer/phone/01_new_form.png` | `/phone_verification` 電話番号認証フォーム | 取得済み |
| `docs/user_manual/images/customer/phone/02_new_filled.png` | 電話番号認証フォーム入力済み。SMS（ショートメッセージ）送信は未実行 | 取得済み |

### ホーム検索・詳細画面

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/customer/home/01_booths_index.png` | `/?mode=booths` booth（ブース）一覧 | 取得済み |
| `docs/user_manual/images/customer/home/02_booth_search.png` | `/?mode=booths&q=サブ` booth（ブース）検索 | 取得済み |
| `docs/user_manual/images/customer/home/03_stores_index.png` | `/?mode=stores` Store（店舗）一覧 | 取得済み |
| `docs/user_manual/images/customer/home/04_users_index.png` | `/?mode=users` user（ユーザー）一覧 | 取得済み |
| `docs/user_manual/images/customer/stores/01_show.png` | `/stores/:id` 店舗詳細 | 取得済み |
| `docs/user_manual/images/customer/users/01_cast_show.png` | `/users/:id` cast（配信者）プロフィール | 取得済み |
| `docs/user_manual/images/customer/booths/01_offline_show.png` | `/booths/:id` offline（オフライン）ブース詳細 | 取得済み |

### live（配信中）視聴・ポイント・お気に入り

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/customer/live/01_live_viewer.png` | `/booths/:id` viewer（視聴者）向け live UI（配信視聴画面） | 取得済み |
| `docs/user_manual/images/customer/live/02_comment_filled.png` | コメント入力済み。送信は未実行 | 取得済み |
| `docs/user_manual/images/customer/live/03_drink_menu.png` | ドリンクメニュー表示。ドリンク送信は未実行 | 取得済み |
| `docs/user_manual/images/customer/wallet/01_purchase_modal.png` | `/wallet/purchases/new` ポイント購入 modal（モーダル）。Stripe（決済）遷移は未実行 | 取得済み |
| `docs/user_manual/images/customer/favorites/01_booths_index.png` | `/favorites/booths` お気に入り booth（ブース）一覧 | 取得済み |
| `docs/user_manual/images/customer/favorites/02_stores_index.png` | `/favorites/stores` お気に入り Store（店舗）一覧 | 取得済み |
| `docs/user_manual/images/customer/favorites/03_users_index.png` | `/favorites/users` お気に入り user（ユーザー）一覧 | 取得済み |

## 第7回で取得済みの system_admin（運営）通常操作スクリーンショット

### dashboard（ダッシュボード）・店舗選択

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/system_admin/dashboard/01_dashboard.png` | `/dashboard` system_admin（運営）カード一覧 | 取得済み |
| `docs/user_manual/images/system_admin/admin_stores/01_store_select.png` | `/admin/stores` 店舗選択画面 | 取得済み |
| `docs/user_manual/images/system_admin/admin_stores/02_after_store_select_dashboard.png` | `マニュアル撮影用店舗` 選択後 `/dashboard` | 取得済み |

### ユーザー管理・紹介コード管理

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/system_admin/users/01_index.png` | `/system_admin/users` ユーザー一覧 | 取得済み |
| `docs/user_manual/images/system_admin/users/02_new_form.png` | `/system_admin/users/new` ユーザー作成フォーム | 取得済み |
| `docs/user_manual/images/system_admin/users/03_filled.png` | ユーザー作成フォーム入力済み | 取得済み |
| `docs/user_manual/images/system_admin/users/04_after_save.png` | ユーザー作成後 `/system_admin/users` 一覧反映 | 取得済み |
| `docs/user_manual/images/system_admin/referral_codes/01_index.png` | `/system_admin/referral_codes` 紹介コード一覧 | 取得済み |
| `docs/user_manual/images/system_admin/referral_codes/02_new_form.png` | `/system_admin/referral_codes/new` 紹介コード作成フォーム | 取得済み |
| `docs/user_manual/images/system_admin/referral_codes/03_filled.png` | 紹介コード作成フォーム入力済み | 取得済み |
| `docs/user_manual/images/system_admin/referral_codes/04_after_save.png` | 紹介コード作成後 `/system_admin/referral_codes` 一覧反映 | 取得済み |

### お知らせ管理・Effect 管理

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/system_admin/notifications/01_index.png` | `/system_admin/notifications` お知らせ一覧 | 取得済み |
| `docs/user_manual/images/system_admin/notifications/02_new_form.png` | `/system_admin/notifications/new` お知らせ作成フォーム | 取得済み |
| `docs/user_manual/images/system_admin/notifications/03_filled.png` | お知らせ作成フォーム入力済み | 取得済み |
| `docs/user_manual/images/system_admin/notifications/04_after_save.png` | お知らせ作成後 `/system_admin/notifications` 一覧反映 | 取得済み |
| `docs/user_manual/images/system_admin/effects/01_index.png` | `/system_admin/effects` Effect 一覧 | 取得済み |
| `docs/user_manual/images/system_admin/effects/02_new_form.png` | `/system_admin/effects/new` Effect 作成フォーム | 取得済み |
| `docs/user_manual/images/system_admin/effects/03_filled.png` | Effect 作成フォーム入力済み | 取得済み |
| `docs/user_manual/images/system_admin/effects/04_after_save.png` | Effect 作成後 `/system_admin/effects` 一覧反映 | 取得済み |

### 店舗BAN・精算・振込 CSV・マニュアル精算

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/system_admin/store_bans/01_index.png` | `/admin/store_bans` 店舗BAN一覧 / フォーム | 取得済み |
| `docs/user_manual/images/system_admin/store_bans/02_form_filled_not_submitted.png` | 店舗BANフォーム入力例。BAN作成は未実行 | 取得済み |
| `docs/user_manual/images/system_admin/settlements/01_index.png` | `/system_admin/settlements` 精算一覧 | 取得済み |
| `docs/user_manual/images/system_admin/settlement_exports/01_index.png` | `/system_admin/settlement_exports` 振込 CSV 一覧 | 取得済み |
| `docs/user_manual/images/system_admin/settlement_exports/02_show.png` | `/system_admin/settlement_exports/:id` 振込 CSV 詳細 | 取得済み |
| `docs/user_manual/images/system_admin/manual_settlements/01_manual_form.png` | `/system_admin/settlements/manual/new` マニュアル精算フォーム | 取得済み |
| `docs/user_manual/images/system_admin/manual_settlements/02_manual_filled.png` | マニュアル精算フォーム入力済み | 取得済み |
| `docs/user_manual/images/system_admin/manual_settlements/03_manual_preview.png` | マニュアル精算 preview（プレビュー）。確定は未実行 | 取得済み |

## 次回撮影すべき画面

1. customer（視聴者）の追加撮影。
   - comment（コメント）送信後の表示更新。
   - drink order（ドリンク注文）送信後の Wallet（ポイント残高）・未消化ドリンク表示。
   - Stripe Checkout（Stripe の決済画面）遷移後の購入完了。
   - SMS OTP（ショートメッセージのワンタイム認証コード）入力。
   - 実 IVS join（Amazon IVS への参加）を伴う映像視聴。
2. cast（配信者）の追加撮影。
   - 実配信開始から終了までの完全フロー。
   - live（配信中）/ away（席外し）への status（状態）変更。
   - 終了済み stream session（配信セッション）がある状態の配信履歴と配信リザルト。
   - customer（視聴者）からの drink order（ドリンク注文）送信と cast（配信者）による消化。
   - サムネ画像アップロード。
3. system_admin（運営）の追加撮影。
   - `/system_admin/settlements/:id` 精算詳細。
   - confirmed（確定済み）精算がある状態の CSV 生成前確認。
   - 店舗BANがある状態の一覧。
   - ユーザー停止、紹介コード無効化、お知らせ無効化、Effect 無効化の確認画面。
4. エラー・注意点として説明すべき画面。
   - 招待 URL 期限切れ。
   - 招待 URL 使用済み。
   - role（権限種別）違いで招待を承認しようとした場合。
   - 権限不足で管理画面を開こうとした場合。
5. mobile（スマートフォン幅）撮影。
6. store_admin（店舗管理者）の追加状態。
   - 通報がある状態。
   - 精算履歴がある状態。
   - 配信者別数値に売上がある状態。
   - 既存ドリンクの編集フォーム。

## 未確認点

- 今回の撮影は desktop（デスクトップ）幅の Chromium のみです。
- 実運用での紹介コード配布方法、招待 URL 共有方法、期限切れ時の問い合わせ先は未確定です。
- system_admin（運営）アカウント作成は画面上の自己登録ではなく、管理・運用手順として別途整理が必要です。
- SMS OTP、Stripe、Banuba / DeepAR、Google Docs 連携は今回の撮影対象外です。
- store_admin（店舗管理者）の通報対応、精算確定、振込 CSV 出力、ブース閉鎖、配信強制終了などの危険操作は未実行です。
- cast（配信者）の配信開始、配信終了、席外し、復帰、ドリンク消化は未実行です。
- customer（視聴者）のコメント送信、ドリンク送信、Stripe Checkout（Stripe の決済画面）での購入完了、SMS OTP 入力、実 IVS join は未実行です。
- system_admin（運営）のユーザー停止、紹介コード無効化、お知らせ無効化、Effect 無効化、店舗BAN作成 / 解除、精算確定、支払済み更新、振込 CSV 生成 / ダウンロード、マニュアル精算確定は未実行です。
