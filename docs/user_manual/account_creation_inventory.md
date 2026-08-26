# アカウント作成経路棚卸し

この文書は、操作マニュアルを「アカウント作成」から書き始めるために、role（権限種別）ごとの作成経路を実コードから整理した第1回調査メモです。

## 全体像

| role（権限種別） | 画面からの作成 | 管理画面からの作成 | seed（初期データ投入処理） | 補足 |
| --- | --- | --- | --- | --- |
| `customer` | `/sign_up` で自己登録 | `system_admin/users#new` で作成可能 | なし | 作成後にログインし、プロフィール編集へ遷移します。 |
| `cast` | `/cast/sign_up?token=...` で招待経由登録 | `system_admin/users#new` で role `cast` として作成可能 | なし | 操作可能にするには、店舗所属とブース紐づけが別途必要です。招待承認では自動作成されます。 |
| `store_admin` | `/stores/new_registration?ref=...` または `/store_admin/sign_up?token=...` | `system_admin/users#new` では作成不可 | なし | 店舗登録では店舗・ユーザー・管理者所属・初期ドリンクを同時作成します。 |
| `system_admin` | 公開登録なし | 既存 `system_admin` が `system_admin/users#new` で作成可能 | `SYSTEM_ADMIN_EMAIL` / `SYSTEM_ADMIN_PASSWORD` で作成可能 | 初回ローカル環境では seed が最も明確です。 |

## 認証まわり

### ログイン / ログアウト

- メールログイン:
  - route（URL経路）: Devise の `new_user_session_path` / `user_session_path`
  - view（画面）: `app/views/devise/sessions/new.html.erb`
  - 根拠: `config/routes.rb`, `app/models/user.rb`
- 電話番号ログイン:
  - route: `/phone_session/new`, `/phone_session/confirm`
  - controller: `app/controllers/phone_sessions_controller.rb`
  - 事前に `User#phone_verified?` が true である必要があります。
  - SMS は `Sms::Sender` 経由で送信され、development（開発環境）の既定は `mock` です。
- ログアウト:
  - `app/views/layouts/_header.html.erb` のドロップダウンから `destroy_user_session_path` に `DELETE` します。
  - Devise 設定では `config.sign_out_via = :delete` です。

### 新規登録

- Devise 標準の registration（新規登録）は `config/routes.rb` で skip（無効化）されています。
- 顧客、cast、store_admin、店舗登録は独自 controller / Form / Service（業務処理を集約するクラス）で処理されます。

### パスワード設定 / パスワード再設定

- 新規登録時または管理画面作成時に `password` / `password_confirmation` を入力します。
- パスワード再設定は Devise の `recoverable` で有効です。
- view:
  - `app/views/devise/passwords/new.html.erb`
  - `app/views/devise/passwords/edit.html.erb`
  - `app/views/devise/mailer/reset_password_instructions.*.erb`
- 有効期限:
  - `config/initializers/devise.rb` の `config.reset_password_within = 48.hours`

### メール確認の有無

- `app/models/user.rb` の Devise モジュールに `confirmable` はありません。
- `db/schema.rb` / migration（DB変更ファイル）に confirmation token 系の users カラムは確認できませんでした。
- `config/locales/devise.ja.yml` には confirmations 用文言がありますが、Devise 標準の文言が残っているだけで、実コード上はメール確認機能として有効化されていません。

### 招待制の有無

- `cast` と追加の `store_admin` は招待経由の登録・承認フローがあります。
- 招待は 1 週間・ワンタイムです。
- 対象:
  - `StoreCastInvitation`
  - `StoreAdminInvitation`
- 根拠:
  - `app/models/store_cast_invitation.rb`
  - `app/models/store_admin_invitation.rb`
  - `app/services/store_cast_invitations/issue_invitation.rb`
  - `app/services/store_admin_invitations/issue_invitation.rb`

### 外部認証の有無

- `omniauthable` は `app/models/user.rb` にありません。
- `config/initializers/devise.rb` の OmniAuth 設定はコメントアウトされています。
- `Gemfile` / `Gemfile.lock` に Devise はありますが、今回確認範囲では外部認証 provider（GitHub / Google など）は見当たりませんでした。

## ロール別アカウント作成方法

### customer（視聴者）

画面作成:

- route: `GET /sign_up`, `POST /sign_up`
- controller: `app/controllers/customers/registrations_controller.rb`
- form: `app/forms/customers/registration_form.rb`
- service: `app/services/customers/register_customer.rb`
- view: `app/views/customers/registrations/new.html.erb`

作成内容:

- `User` を `role: :customer` で作成します。
- 作成後は `sign_in(@form.user)` で自動ログインします。
- 保存済み遷移先がなければ `edit_profile_path` へ遷移します。

管理画面作成:

- `system_admin/users#new` から role `customer` を選択して作成できます。
- 根拠: `app/controllers/system_admin/users_controller.rb`, `test/integration/system_admin_users_test.rb`

注意点:

- customer 登録では店舗・ブース・所属データは作成されません。
- マニュアル撮影用には、視聴対象の店舗・ブース・配信状態を別途用意する必要があります。

### cast（配信者）

招待経由の画面作成:

- 招待確認 route: `GET /cast_invitations/:token`
- 新規登録 route: `GET /cast/sign_up?token=...`, `POST /cast/sign_up?token=...`
- controller:
  - `app/controllers/cast_invitations_controller.rb`
  - `app/controllers/casts/registrations_controller.rb`
- form: `app/forms/casts/registration_form.rb`
- service:
  - `app/services/casts/register_cast.rb`
  - `app/services/store_cast_invitations/accept_invitation.rb`

作成内容:

- `Casts::RegisterCast` は `User` を `role: :cast` で作成します。
- 招待承認時に `StoreMembership` を `membership_role: :cast` で作成します。
- 招待承認時に `Booth` を作成します。
- 招待承認時に `Booths::ProvisionIvsStageService` で IVS Stage（Amazon IVS の配信ルーム実体）を作成します。
- 招待承認時に `BoothCast` を作成し、cast とブースを紐づけます。
- 新規 cast が招待承認した場合、プロフィール編集後にブース編集へ進むテストがあります。

既存アカウントでの承認:

- 既存の `cast` は招待 URL にログイン状態でアクセスし、承認できます。
- `customer` など cast 以外では承認できません。

管理画面作成:

- `system_admin/users#new` で role `cast` のユーザー自体は作成可能です。
- ただし、その時点では店舗所属・ブース・`BoothCast` が作成されません。
- マニュアル撮影用の「配信できる cast」を作るには、招待承認フローを使うか、同等の関連データを runner（Rails コード実行）/ console（対話実行）で作る必要があります。

注意点:

- cast 招待承認は IVS Stage 作成を伴います。ローカル撮影で AWS（Amazon Web Services）を呼ばない方針にする場合、次回までに回避方法を決める必要があります。

### store_admin（店舗管理者）

店舗登録による作成:

- route: `GET /stores/new_registration?ref=...`, `POST /stores/registrations`
- controller: `app/controllers/stores/registrations_controller.rb`
- form: `app/forms/stores/registration_form.rb`
- service: `app/services/stores/register_store_admin.rb`
- view: `app/views/stores/registrations/new.html.erb`

作成内容:

- `ReferralCode` が使用可能である必要があります。紹介コード未入力時は `0000` を使用します。
- `Store` を作成します。
- 初期 `DrinkItem` を作成します。
- `User` を `role: :store_admin` で作成します。
- `StoreMembership` を `membership_role: :admin` で作成します。
- 作成後は自動ログインし、`session[:current_store_id]` を設定して `edit_admin_store_path(@form.store)` へ遷移します。

店舗管理者招待による作成:

- 招待確認 route: `GET /store_admin_invitations/:token`
- 新規登録 route: `GET /store_admin/sign_up?token=...`, `POST /store_admin/sign_up?token=...`
- controller:
  - `app/controllers/store_admin_invitations_controller.rb`
  - `app/controllers/store_admins/registrations_controller.rb`
- form: `app/forms/store_admins/registration_form.rb`
- service:
  - `app/services/store_admins/register_store_admin.rb`
  - `app/services/store_admin_invitations/accept_invitation.rb`

作成内容:

- `StoreAdmins::RegisterStoreAdmin` は `User` を `role: :store_admin` で作成します。
- 招待承認時に `StoreMembership` を `membership_role: :admin` で作成します。
- 承認後に `session[:current_store_id]` が招待対象店舗に設定されます。

管理画面作成:

- `system_admin/users#new` では `store_admin` は作成・変更不可です。
- 根拠:
  - `app/controllers/system_admin/users_controller.rb` の `role_options`
  - `test/integration/system_admin_users_test.rb`

注意点:

- 店舗登録の紹介コード入力は任意です。未入力時は `0000` の紹介コードで登録します。
- 招待経由で作った store_admin は、承認するまで店舗所属がありません。

### system_admin（運営）

seed（初期データ投入処理）:

- `db/seeds/master_data.rb` で `SYSTEM_ADMIN_EMAIL` と `SYSTEM_ADMIN_PASSWORD` がある場合のみ作成されます。
- role は `:system_admin` に設定されます。

管理画面作成:

- 既存 `system_admin` は `system_admin/users#new` から別の `system_admin` を作成できます。
- 自分自身の降格不可、最後の `system_admin` の降格不可が実装されています。
- 根拠:
  - `app/controllers/system_admin/users_controller.rb`
  - `test/integration/system_admin_users_test.rb`

画面作成:

- 公開画面からの `system_admin` 登録 route は確認できませんでした。

## ローカルで撮影用アカウントを作る場合の方針案

安全方針:

- production（本番環境）では実行しない。
- ローカルまたは test / development 専用 DB を使う。
- メールアドレスは `manual+role@example.test` のような撮影専用値にする。
- 既存データを壊さないため、削除ではなく専用データを作り直せる runner（Rails コード実行）を用意する方針が安全です。
- 今回はスクリプト作成禁止のため、実装は次回以降に回します。

推奨データ作成順:

1. seed（初期データ投入処理）または runner で `system_admin` を作る。
2. `system_admin` で紹介コードを作る、または runner で `ReferralCode` を作る。
3. 店舗登録画面から `store_admin` と `Store` を作る。
4. 店舗管理画面から cast 招待・店舗管理者招待を発行する。
5. cast 招待 URL から cast を作る。
6. customer は `/sign_up` から作る。
7. 必要なら runner で wallet（ポイント残高）や配信状態を撮影用に整える。

外部サービスの注意:

- IVS Stage 作成:
  - cast 招待承認と admin のブース作成では `Booths::ProvisionIvsStageService` が走り、通常は AWS IVS を呼びます。
  - ローカル撮影で AWS を呼ばない場合、次回 Playwright 実装前に fake（代替実装）を注入する方法、または runner で `ivs_stage_arn` を疑似値で埋める方法を検討します。
- SMS:
  - development の既定は `mock` 送信です。
  - OTP（ワンタイム認証コード）をログから取得するか、撮影用ユーザーに `phone_number` / `phone_verified_at` を直接設定する方針が必要です。
- Stripe:
  - ポイント購入は Stripe Checkout に遷移します。
  - 撮影では実決済を避け、購入画面までに留めるか、撮影用 wallet を runner で付与する方針が安全です。
- Banuba / DeepAR:
  - 配信画面の画面加工は token / license が未設定だと制限される可能性があります。
  - 第2回では「配信画面のスクリーンショットで画面加工まで含めるか」を決める必要があります。

## 未確認 / TODO

- ローカル環境で IVS Stage 作成をどう回避するかは未確定です。
- Playwright（ブラウザ自動操作）用の認証済み状態を、UI ログインで作るか、Rails runner で cookie/session を用意するかは未確定です。
- 店舗登録の紹介コードを、画面操作で用意するか runner で用意するかは未確定です。
- 電話番号ログインをマニュアル対象に含める範囲は未確定です。
- パスワード再設定メールのローカル確認は、development の `letter_opener_web` を使う想定ですが、今回はブラウザ確認していません。
