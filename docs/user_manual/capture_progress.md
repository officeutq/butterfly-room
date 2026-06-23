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
| `docs/user_manual/images/account_creation/store_admin_registration/03_after_registration_store_edit.png` | 登録後 `/admin/stores/:id/edit` | 取得済み |

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

## 今回取得できなかったもの

- mobile（スマートフォン幅）でのアカウント作成フロー。
- 招待 URL の期限切れ / 使用済み / role（権限種別）違いのエラー画面。
- SMS OTP（ショートメッセージのワンタイム認証コード）入力フロー。
- Stripe（決済）完了フロー。
- cast（配信者）の配信開始から終了までの完全フロー。

## 次回撮影すべき画面

1. role（権限種別）別の通常操作画面。
   - customer（視聴者）: ブース詳細、配信視聴、コメント、ドリンク送信、ポイント購入導線。
   - cast（配信者）: ブース詳細、ブース編集、配信準備、配信開始、配信終了、ドリンク消化。
   - store_admin（店舗管理者）: ブース管理、cast 管理、ドリンクメニュー管理、招待管理、売上・精算関連。
   - system_admin（運営）: ユーザー管理、紹介コード管理、通知管理、Effect 管理、精算管理。
2. エラー・注意点として説明すべき画面。
   - 招待 URL 期限切れ。
   - 招待 URL 使用済み。
   - role（権限種別）違いで招待を承認しようとした場合。
   - 権限不足で管理画面を開こうとした場合。
3. mobile（スマートフォン幅）撮影。

## 未確認点

- 今回の撮影は desktop（デスクトップ）幅の Chromium のみです。
- 実運用での紹介コード配布方法、招待 URL 共有方法、期限切れ時の問い合わせ先は未確定です。
- system_admin（運営）アカウント作成は画面上の自己登録ではなく、管理・運用手順として別途整理が必要です。
- SMS OTP、Stripe、Banuba / DeepAR、Google Docs 連携は今回の撮影対象外です。
