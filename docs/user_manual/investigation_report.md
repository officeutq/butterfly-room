# 第1回 操作マニュアル作成調査レポート

今回は、エンドユーザー向け操作マニュアルを作るために、認証、role（権限種別）、アカウント作成経路、マニュアル化対象画面、Playwright（ブラウザ自動操作）導入見込みを実コードから確認しました。アプリ本体の挙動変更、Playwright 実装、アカウント作成スクリプト作成、スクリーンショット取得は行っていません。

## 確認した既存ドキュメント

- `docs/02_要件定義書.md`
  - 基本ロール、ロール階層、cast 招待方針を確認しました。
- `docs/03_基本設計_Phase1.md`
  - `users.role`、招待、停止ユーザー、最後の `system_admin` 保護、キャスト所属、ブース紐づけ方針を確認しました。
- `docs/04_Rails設計.md`
  - Devise（Rails の認証ライブラリ）、Service（業務処理を集約するクラス）方針、route（URL経路）方針を確認しました。
- `docs/05_WebRTC_配信シグナリング設計.md`
  - 配信が `stream_session` 単位であり、IVS Stage（Amazon IVS の配信ルーム実体）を使うことを確認しました。
- `docs/06_配信映像設計.md`
  - 配信映像まわりの前提を確認しました。
- `docs/07_モード導線設計.md`
  - `current_booth` / `current_store` とロール別導線の設計を確認しました。
- `docs/08_画面加工設計.md`
  - Banuba / DeepAR など画面加工の前提を確認しました。
- `docs/09_最新ディレクトリ構成.md`
  - 調査対象の controller / service / view の位置を確認しました。

## 確認した主な実コード

認証 / role:

- `config/routes.rb`
- `config/initializers/devise.rb`
- `app/models/user.rb`
- `app/controllers/application_controller.rb`
- `app/helpers/application_helper.rb`
- `db/migrate/20260111041958_create_users.rb`
- `db/migrate/20260111050008_add_devise_to_users.rb`
- `db/migrate/20260220083903_add_deleted_at_to_users.rb`
- `db/migrate/20260414114618_add_phone_number_to_users.rb`
- `db/schema.rb`

アカウント作成:

- `app/controllers/customers/registrations_controller.rb`
- `app/forms/customers/registration_form.rb`
- `app/services/customers/register_customer.rb`
- `app/controllers/stores/registrations_controller.rb`
- `app/forms/stores/registration_form.rb`
- `app/services/stores/register_store_admin.rb`
- `app/controllers/casts/registrations_controller.rb`
- `app/forms/casts/registration_form.rb`
- `app/services/casts/register_cast.rb`
- `app/controllers/store_admins/registrations_controller.rb`
- `app/forms/store_admins/registration_form.rb`
- `app/services/store_admins/register_store_admin.rb`
- `app/controllers/system_admin/users_controller.rb`
- `db/seeds/master_data.rb`

招待:

- `app/models/store_cast_invitation.rb`
- `app/models/store_admin_invitation.rb`
- `app/controllers/admin/cast_invitations_controller.rb`
- `app/controllers/admin/store_admin_invitations_controller.rb`
- `app/controllers/cast_invitations_controller.rb`
- `app/controllers/store_admin_invitations_controller.rb`
- `app/services/store_cast_invitations/issue_invitation.rb`
- `app/services/store_cast_invitations/accept_invitation.rb`
- `app/services/store_admin_invitations/issue_invitation.rb`
- `app/services/store_admin_invitations/accept_invitation.rb`

ロール別画面 / 権限:

- `app/views/dashboard/show.html.erb`
- `app/controllers/admin/base_controller.rb`
- `app/controllers/cast/base_controller.rb`
- `app/controllers/system_admin/base_controller.rb`
- `app/services/authorization/booth_policy.rb`
- `app/services/authorization/stream_session_policy.rb`
- `app/services/authorization/viewer_policy.rb`
- `app/controllers/booths_controller.rb`
- `app/controllers/home_controller.rb`
- `app/controllers/wallet/purchases_controller.rb`

テスト:

- `test/integration/authentication_required_test.rb`
- `test/integration/customer_sign_up_test.rb`
- `test/integration/cast_invitation_flow_test.rb`
- `test/integration/store_cast_invitation_flow_test.rb`
- `test/integration/store_admin_invitation_flow_test.rb`
- `test/integration/system_admin_users_test.rb`
- `test/integration/role_hierarchy_access_test.rb`
- `test/integration/phone_login_flow_test.rb`
- `test/integration/phone_verification_flow_test.rb`
- `test/services/stores/register_store_admin_test.rb`
- `test/services/authorization/stream_session_policy_booth_casts_test.rb`

開発 / テスト基盤:

- `Gemfile`
- `package.json`
- `Procfile.dev`
- `bin/dev`
- `bin/ci`
- `config/ci.rb`
- `.github/workflows/ci.yml`

## 分かったこと

### ロール一覧

実コード上の role（権限種別）は次の4つです。

- `customer`（視聴者）
- `cast`（配信者）
- `store_admin`（店舗管理者）
- `system_admin`（運営）

`app/models/user.rb` の enum（列挙型）と `ROLE_LEVELS` で定義され、`at_least?` による階層判定があります。

### アカウント作成経路

- `customer` は `/sign_up` から自己登録できます。
- `cast` は招待 URL 経由の `/cast/sign_up?token=...` で作成できます。既存 cast も招待承認できます。
- `store_admin` は店舗登録 `/stores/new_registration?ref=...` で作る経路と、店舗管理者招待 `/store_admin/sign_up?token=...` で作る経路があります。
- `system_admin` は seed（初期データ投入処理）で作るか、既存 system_admin のユーザー管理画面から作ります。
- `system_admin/users#new` では `customer`、`cast`、`system_admin` は作れますが、`store_admin` は明示的に除外されています。

### ログイン後の入口

- `/dashboard` が共通の操作入口です。
- フッターの「ダッシュボード」は `dashboard_path_for(current_user)` を使い、実装上は常に `/dashboard` です。
- メールログイン / 電話番号ログインの保存済み遷移先なしのテストでは `root_path` へ遷移しています。
- 未ログインで保護された画面へアクセスした場合、ログイン後に元画面へ戻るテストがあります。

### 招待フロー

- cast 招待と store_admin 招待は、24時間・ワンタイムです。
- cast 招待承認では、`StoreMembership`、`Booth`、IVS Stage、`BoothCast` が作成されます。
- store_admin 招待承認では、`StoreMembership` が作成され、`current_store` が招待対象店舗になります。
- role が違うユーザーでは招待承認できません。

### Playwright 導入見込み

- `package.json` に Playwright はありません。
- `Gemfile` には Capybara（Rails のブラウザテスト支援）と Selenium（ブラウザ駆動）があります。
- `test/system` は確認できませんでした。
- `config/ci.rb` では system test（ブラウザテスト）は任意コメントアウトです。
- ローカル起動は README 上では Docker Compose、`Procfile.dev` / `bin/dev` 上では Rails server + CSS watch です。

## 分からなかったこと / 未確認

- ブラウザ上でのログイン直後の実表示は未確認です。実コード上は保存済み遷移先がある場合とない場合で遷移が変わります。
- Playwright で認証済み状態を作る方法は未確定です。
- ローカル撮影用データ作成を UI 操作だけで行うか、runner（Rails コード実行）で行うかは未確定です。
- IVS Stage 作成をローカルでどう回避するかは未確定です。
- SMS の OTP（ワンタイム認証コード）を Playwright でどう取得するかは未確定です。
- Stripe Checkout をスクリーンショット対象に含めるかは未確定です。
- Banuba / DeepAR を使う配信画面の撮影で、token / license 未設定時の扱いは未確認です。
- `sales` は要件定義書に「基本ロールとは別の独立軸」とありますが、今回確認した実コードでは role enum としては見つかっていません。

## 次に実装すべき作業

1. Playwright（ブラウザ自動操作）導入方針を決める。
   - npm dependency として導入するか、既存 Capybara / Selenium を使うかを決めます。
2. 撮影用 seed / runner 方針を決める。
   - 既存アプリ本体に影響を与えない撮影専用データ作成手順が必要です。
3. IVS Stage 作成のローカル回避策を決める。
   - fake client（代替クライアント）を使うか、撮影用 runner で `ivs_stage_arn` を疑似値にするかを決めます。
4. SMS OTP の取得方法を決める。
   - ログ取得、DB 参照、または撮影用ユーザーの電話番号認証済み固定化を検討します。
5. スクリーンショット一覧を確定する。
   - `manual_outline.md` の優先度A/Bから始めるのがよさそうです。
6. 操作マニュアル本文のドラフトを作る。
   - まずアカウント作成、ログイン、ダッシュボード、ロール別初回操作から着手します。

## Playwright 実装前に確認すべき点

- Playwright の対象ブラウザを Chromium に絞るか。
- Rails server の起動方法を Docker Compose にするか、`bin/dev` にするか。
- CSS build（`npm run build:css`）を事前実行するか、`bin/dev` の watch に任せるか。
- 画像アップロードや ActiveStorage（Rails のファイル保存機能）を撮影対象に含めるか。
- カメラ / マイク権限が必要な cast 配信画面を、実デバイスなしでどこまで撮影するか。
- Stripe / SMS / IVS / Banuba / DeepAR など外部サービス依存をどの範囲で回避するか。
- スクリーンショット保存先とファイル命名規則。

## 今回作成したドキュメント

- `docs/user_manual/role_inventory.md`
- `docs/user_manual/account_creation_inventory.md`
- `docs/user_manual/manual_outline.md`
- `docs/user_manual/investigation_report.md`

## 変更範囲

- docs（ドキュメント）追加のみです。
- アプリの実装、route（URL経路）、view（画面）、test（テスト）は変更していません。
