# 第3回 アカウント作成フロー撮影記録

この文書は、操作マニュアルに載せるアカウント作成フローを Playwright（ブラウザ自動操作）で撮影した記録です。撮影は development（開発環境）で実施し、production（本番環境）向けの挙動は変更していません。

> 2026-09-06追記: この記録の店舗登録部分は旧フローです。現在は登録後に初回店舗設定へ進み、保存・公開後にサンクス、ダッシュボードへ遷移します。撮影specは新フローへ更新済みで、画像は再撮影待ちです。`03_after_registration_store_edit.png`は現行マニュアルから参照しません。

## 撮影コマンド

```bash
docker compose exec -T app bin/rails manual_capture:prepare
npm run manual:capture:accounts
```

今回成功した実行 ID は `20260623002322` です。`MANUAL_CAPTURE_RUN_ID` を指定しない場合、Playwright spec（ブラウザ自動操作テスト定義）が実行時刻から一意な ID を作り、`manual+account_flow_...@example.test` の撮影用メールアドレスを使います。

## 使用した撮影用メールアドレス

| フロー | メールアドレス |
| --- | --- |
| customer（視聴者）自己登録 | `manual+account_flow_customer_20260623002322@example.test` |
| store_admin（店舗管理者）店舗登録 | `manual+account_flow_store_admin_registration_20260623002322@example.test` |
| cast（配信者）招待登録 | `manual+account_flow_cast_invitation_20260623002322@example.test` |
| 追加 store_admin（店舗管理者）招待登録 | `manual+account_flow_store_admin_invitation_20260623002322@example.test` |

固定の事前ログイン用 store_admin（店舗管理者）は `manual_capture:prepare` が作成する `manual+store_admin@example.test` を使用しました。

## 撮影したフローと実際の遷移先

| フロー | 開始画面 | 登録後の遷移 |
| --- | --- | --- |
| customer（視聴者）自己登録 | `/sign_up` | `/profile/edit` |
| store_admin（店舗管理者）店舗登録 | `/stores/new_registration?ref=MANUAL-CAPTURE-LOCAL` | 撮影時点は`/admin/stores/:id/edit`。現行は初回店舗設定 → 登録完了 → `/dashboard` |
| cast（配信者）招待登録 | `/admin/cast_invitations` で招待 URL 発行後、`/cast_invitations/:token` | `/cast_invitations/:token` → 承認後 `/profile/edit` → 更新後 `/cast/booths/:id/edit` → ブース更新後 `/` |
| 追加 store_admin（店舗管理者）招待登録 | `/admin/store_admin_invitations` で招待 URL 発行後、`/store_admin_invitations/:token` | `/store_admin_invitations/:token` → 承認後 `/dashboard` |

根拠コード:

- `config/routes.rb`
- `app/controllers/customers/registrations_controller.rb`
- `app/controllers/stores/registrations_controller.rb`
- `app/controllers/casts/registrations_controller.rb`
- `app/controllers/store_admins/registrations_controller.rb`
- `app/controllers/cast_invitations_controller.rb`
- `app/controllers/store_admin_invitations_controller.rb`
- `app/services/store_cast_invitations/accept_invitation.rb`
- `app/services/booths/provision_ivs_stage_service.rb`

## 保存したスクリーンショット

### customer（視聴者）自己登録

- `images/account_creation/customer/01_signup_form.png`
- `images/account_creation/customer/02_signup_filled.png`
- `images/account_creation/customer/03_after_signup_profile_edit.png`

### store_admin（店舗管理者）店舗登録

- `images/account_creation/store_admin_registration/01_registration_form.png`
- `images/account_creation/store_admin_registration/02_registration_filled.png`
- `images/account_creation/store_admin_registration/03_after_registration_store_edit.png`（旧フロー・現行マニュアルでは参照しない）

新フローで再撮影するファイル:

- `images/account_creation/store_admin_registration/03_after_registration_initial_setup.png`
- `images/account_creation/store_admin_registration/04_after_initial_setup_thanks.png`
- `images/account_creation/store_admin_registration/05_after_registration_dashboard.png`

### cast（配信者）招待登録

- `images/account_creation/cast_invitation/01_admin_invitation_form.png`
- `images/account_creation/cast_invitation/02_admin_invitation_filled.png`
- `images/account_creation/cast_invitation/03_admin_invitation_issued.png`
- `images/account_creation/cast_invitation/04_invitation_guest.png`
- `images/account_creation/cast_invitation/05_signup_form.png`
- `images/account_creation/cast_invitation/06_signup_filled.png`
- `images/account_creation/cast_invitation/07_after_signup_invitation.png`
- `images/account_creation/cast_invitation/08_after_accept_profile_edit.png`
- `images/account_creation/cast_invitation/09_profile_filled.png`
- `images/account_creation/cast_invitation/10_after_profile_booth_edit.png`
- `images/account_creation/cast_invitation/11_booth_filled.png`
- `images/account_creation/cast_invitation/12_after_booth_update_home.png`

### 追加 store_admin（店舗管理者）招待登録

- `images/account_creation/store_admin_invitation/01_admin_invitation_form.png`
- `images/account_creation/store_admin_invitation/02_admin_invitation_issued.png`
- `images/account_creation/store_admin_invitation/03_invitation_guest.png`
- `images/account_creation/store_admin_invitation/04_signup_form.png`
- `images/account_creation/store_admin_invitation/05_signup_filled.png`
- `images/account_creation/store_admin_invitation/06_after_signup_invitation.png`
- `images/account_creation/store_admin_invitation/07_after_accept_dashboard.png`

## 外部サービス依存の回避

cast invitation（配信者招待）承認時は `StoreCastInvitations::AcceptInvitation` が `Booths::ProvisionIvsStageService` を呼びます。今回、production（本番環境）以外で、店舗名に `manual` または `マニュアル撮影用` を含むマニュアル撮影データだけ、AWS（Amazon Web Services）を呼ばず疑似 `ivs_stage_arn` を保存する分岐を追加しました。

疑似 ARN の形式:

```text
arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local-booth-<booth_id>
```

production（本番環境）ではこの分岐は無効です。Stripe（決済）、SMS（ショートメッセージ）、Banuba / DeepAR（画面加工）は今回の撮影対象外です。

## 未確認点

- mobile（スマートフォン幅）でのアカウント作成画面は未撮影です。
- メール確認フローは実コード上見つかっていませんが、メール配送を伴う確認は未撮影です。
- SMS OTP（ワンタイム認証コード）を使う電話番号ログイン / 電話番号認証は未撮影です。
- 招待 URL の期限切れ・使用済みエラー画面は未撮影です。
- 画面文言は実画面を撮影しましたが、読者向け本文としての説明文は `account_creation_manual_draft.md` で TODO を残しています。
