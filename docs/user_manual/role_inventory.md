# ロール棚卸し

この文書は、エンドユーザー向け操作マニュアル作成のために、実コードを根拠に role（権限種別）を整理した第1回調査メモです。推測で確定できない箇所は TODO / 未確認 として残します。

現行実装に基づく画面ごとのアクセス可否は、[11_画面アクセス権限マトリクス.md](../11_画面アクセス権限マトリクス.md) を参照してください。

## 前提

- 認証主体は `User` の単一テーブルです。
- role（権限種別）は enum（列挙型）で、`customer < cast < store_admin < system_admin` の階層です。
- ログイン後の操作入口として `/dashboard` があり、フッターの「ダッシュボード」から到達します。
- メールアドレスとパスワードによる Devise（Rails の認証ライブラリ）認証が基本です。
- 電話番号認証済みユーザーは、電話番号 + SMS の OTP（ワンタイム認証コード）でもログインできます。

## ロール一覧

| role（権限種別） | 画面上の説明 | 階層 | 主な対象 | ログイン後の主な入口 |
| --- | --- | ---: | --- | --- |
| `customer` | 視聴者 | 0 | 配信を探す、視聴する、コメントする、ポイント購入、ドリンク送信 | `/`（ホーム）、`/dashboard` |
| `cast` | 配信者 | 1 | 所属ブースの確認、ブース編集、配信、配信履歴、ドリンク消化 | `/dashboard`、`/cast/booths`、選択中ブースの cast 画面 |
| `store_admin` | 店舗管理者 | 2 | 自店の店舗設定、ブース管理、キャスト招待、店舗管理者招待、ドリンク、精算確認 | `/dashboard`、`/admin/...` |
| `system_admin` | 運営 | 3 | ユーザー、紹介コード、Effect、お知らせ、精算、店舗BANなどの運用管理 | `/dashboard`、`/system_admin/...` |

## 定義箇所

- `app/models/user.rb`
  - `enum :role, { customer: 0, cast: 1, store_admin: 2, system_admin: 3 }`
  - `ROLE_LEVELS` と `at_least?` で階層判定を行います。
  - `deleted_at` が入ったユーザーは `active_for_authentication?` でログイン不可です。
- `db/migrate/20260111041958_create_users.rb`
  - `users.role` は `integer`、`null: false` です。
- `docs/02_要件定義書.md`
  - 基本ロールと階層 `system_admin > store_admin > cast > customer` が記載されています。
- `docs/03_基本設計_Phase1.md`
  - `users.role` によるロール定義、停止ユーザーのログイン不可、最後の `system_admin` 保護方針が記載されています。
- `config/locales/ja.yml`
  - `user.role` は「権限」として定義されています。
- `app/helpers/application_helper.rb`
  - `user_role_label` で `customer=視聴者`、`cast=配信者`、`store_admin=店舗管理者`、`system_admin=運営` を返します。

## 認証と共通入口

- `config/routes.rb`
  - `devise_for :users, skip: %i[registrations]` で Devise 標準の新規登録は使っていません。
  - 顧客登録は `/sign_up`、cast 登録は `/cast/sign_up`、store_admin 登録は `/store_admin/sign_up`、店舗登録は `/stores/new_registration` に独自 route があります。
  - ログアウトは Devise の `destroy_user_session_path` で、HTTP method は `DELETE` です。
- `app/models/user.rb`
  - Devise モジュールは `database_authenticatable`、`recoverable`、`rememberable`、`validatable` です。
  - `confirmable` は有効化されていません。メール確認用カラムも確認できませんでした。
  - `omniauthable` は有効化されていません。外部認証は現時点では未導入です。
- `app/controllers/application_controller.rb`
  - 原則 `before_action :authenticate_user!` でログイン必須です。
  - `after_sign_in_path_for` は、保存済み遷移先があればそこへ戻し、なければ Devise 標準の遷移に委ねます。
  - ログイン時に、選択可能な店舗・ブースが1つだけなら `session[:current_store_id]` / `session[:current_booth_id]` を自動設定します。
- `app/helpers/application_helper.rb`
  - `dashboard_path_for(_user)` は常に `dashboard_path` を返します。
- `test/integration/authentication_required_test.rb`
  - 未ログインで `/dashboard`、`/admin/...`、`/system_admin/...` にアクセスするとログイン画面へリダイレクトされます。
  - 未ログインでブース詳細へアクセス後にログインすると、元のブースへ戻るテストがあります。
- `test/integration/phone_login_flow_test.rb`
  - メールログイン、電話番号ログインとも、保存済み遷移先がない場合は `root_path` にリダイレクトされるテストがあります。

TODO: 「ログイン直後のトップ画面」はブラウザ上の実挙動確認が必要です。実コード上は保存済み遷移先がない場合 Devise 標準遷移で `root_path` が使われる一方、操作入口は `/dashboard` に集約されています。

## 権限差

### customer（視聴者）

- 利用できる主な画面:
  - `/` ホーム
  - `/dashboard` ダッシュボード
  - `/profile/edit` プロフィール編集
  - `/phone_verification` 電話番号認証
  - `/favorites/...` お気に入り
  - `/stores/:id` 店舗詳細
  - `/booths/:id` ブース詳細
  - `/wallet/purchases/new` ポイント購入
- 主な操作:
  - 配信視聴、コメント投稿、ドリンク送信、ポイント購入。
  - 店舗BAN対象の場合、対象店舗の表示・操作に制限があります。
- 根拠:
  - `app/views/dashboard/show.html.erb`
  - `app/controllers/home_controller.rb`
  - `app/controllers/booths_controller.rb`
  - `app/services/authorization/viewer_policy.rb`
  - `app/controllers/stream_sessions/comments_controller.rb`
  - `app/controllers/stream_sessions/drink_orders_controller.rb`

### cast（配信者）

- 利用できる主な画面:
  - customer（視聴者）向け画面
  - `/cast/booths` ブース一覧
  - `/cast/booths/:id` ブース情報
  - `/cast/booths/:id/edit` ブース編集
  - `/cast/booths/:id/live` 配信画面
  - `/cast/booths/:booth_id/stream_sessions` 配信履歴
- 主な操作:
  - 自分に紐づいたブースの選択、ブース編集、配信開始、席外し、復帰、終了、ドリンク消化。
  - `BoothCast` に紐づいていないブースは操作不可です。
- 根拠:
  - `app/controllers/cast/base_controller.rb`
  - `app/controllers/cast/booths_controller.rb`
  - `app/controllers/cast/booths/stream_sessions_controller.rb`
  - `app/controllers/cast/drink_orders_controller.rb`
  - `app/services/authorization/booth_policy.rb`
  - `test/integration/role_hierarchy_access_test.rb`

### store_admin（店舗管理者）

- 利用できる主な画面:
  - customer / cast 相当の下位機能の一部
  - `/admin/stores` 店舗選択
  - `/admin/stores/:id/edit` 店舗設定編集
  - `/admin/booths` ブース管理
  - `/admin/casts` キャスト一覧
  - `/admin/cast_invitations` キャスト招待
  - `/admin/store_admin_invitations` 店舗管理者招待
  - `/admin/drink_items` ドリンクメニュー
  - `/admin/cast_metrics` 配信者別数値一覧
  - `/admin/comment_reports` 通報一覧
  - `/admin/payout_account/edit` 振込先口座設定
  - `/admin/settlements` 精算（予定・履歴）
- 主な操作:
  - 自店に対する店舗・ブース・キャスト・ドリンク・精算の管理。
  - `StoreMembership` の `membership_role: :admin` がある店舗のみ操作できます。
  - `store_admin` は cast namespace にも入れますが、自店ブースに限られます。
- 根拠:
  - `app/controllers/admin/base_controller.rb`
  - `app/controllers/admin/stores_controller.rb`
  - `app/controllers/admin/booths_controller.rb`
  - `app/controllers/admin/cast_invitations_controller.rb`
  - `app/controllers/admin/store_admin_invitations_controller.rb`
  - `app/views/dashboard/show.html.erb`
  - `test/integration/role_hierarchy_access_test.rb`

### system_admin（運営）

- 利用できる主な画面:
  - 下位ロールの画面
  - `/system_admin/users` ユーザー管理
  - `/system_admin/referral_codes` 紹介コード管理
  - `/system_admin/notifications` お知らせ管理
  - `/system_admin/effects` Effect 管理
  - `/system_admin/settlements` 精算一覧
  - `/system_admin/settlement_exports` 振込 CSV
  - `/system_admin/settlements/manual/new` マニュアル精算（テスト）
  - `/admin/store_bans` 店舗BAN
- 主な操作:
  - 運用管理画面にアクセスできます。
  - `admin` namespace では店舗未選択の場合、店舗選択画面へ誘導されます。
  - `system_admin` は `store_admin` をユーザー管理画面から作成できません。
- 根拠:
  - `app/controllers/system_admin/base_controller.rb`
  - `app/controllers/system_admin/users_controller.rb`
  - `app/controllers/system_admin/referral_codes_controller.rb`
  - `app/views/dashboard/show.html.erb`
  - `test/integration/system_admin_users_test.rb`
  - `test/integration/role_hierarchy_access_test.rb`

## ロールごとのダッシュボード表示

`app/views/dashboard/show.html.erb` から確認したカード一覧です。

| 条件 | 表示される主なカード |
| --- | --- |
| `at_least?(:customer)` | プロフィール編集、電話番号認証 |
| `cast? && @cast_booths_count >= 2` | ブース一覧 |
| `at_least?(:cast)` | ブース情報、配信履歴、ブース編集 |
| `at_least?(:store_admin) && @selectable_stores_count >= 2` | 店舗を選択 |
| `at_least?(:store_admin)` | ブース管理、店舗設定編集、キャスト一覧、キャスト招待、店舗管理者招待、配信者別数値一覧、ドリンクメニュー、通報一覧、振込先口座設定、精算 |
| `system_admin?` | 店舗BAN、ユーザー管理、紹介コード管理、お知らせ管理、マニュアル精算、振込CSV、精算一覧、Effect管理 |

## 未確認 / TODO

- ブラウザでの実際の「ログイン直後」表示は未確認です。次回 Playwright（ブラウザ自動操作）導入前に、保存済み遷移先あり / なしの両方を確認します。
- `sales` は要件定義書に「基本ロールとは別の独立軸」とありますが、今回確認した実コードでは role enum としては未実装です。
- 一部画面の細かな入力エラー・成功メッセージは、今回スクリーンショット取得を行っていないため未確認です。
