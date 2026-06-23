# 操作マニュアル目次案

この文書は、第1回調査で確認した実コードをもとにした、エンドユーザー向け操作マニュアルの章立て案です。次回以降に Playwright（ブラウザ自動操作）でスクリーンショット取得を行う前提で、撮影候補も併記します。

## 目次案

1. はじめに
   - Butterflyve の利用者種別
   - role（権限種別）の違い
   - 推奨ブラウザとログインに必要なもの
2. アカウント作成
   - customer（視聴者）アカウントを作成する
   - 店舗登録から store_admin（店舗管理者）を作成する
   - 招待 URL から cast（配信者）アカウントを作成する
   - 招待 URL から store_admin（店舗管理者）アカウントを作成する
   - system_admin（運営）アカウントの準備方法
3. ログイン / ログアウト
   - メールアドレスとパスワードでログインする
   - 電話番号でログインする
   - ログアウトする
   - パスワードを再設定する
4. 共通操作
   - ホームでブース / 店舗 / ユーザーを探す
   - ダッシュボードを開く
   - プロフィールを編集する
   - 電話番号を認証する
   - お知らせを見る
   - お気に入りを管理する
5. customer（視聴者）向け操作
   - ブース詳細を開く
   - 配信を視聴する
   - コメントする
   - ポイントを購入する
   - ドリンクを送る
   - 店舗BANなどで操作できない場合
6. cast（配信者）向け操作
   - 招待を承認する
   - プロフィールを整える
   - ブース情報を確認する
   - ブースを編集する
   - 配信を開始する
   - 席外し / 復帰を行う
   - 配信を終了する
   - ドリンクを消化する
   - 配信履歴を確認する
7. store_admin（店舗管理者）向け操作
   - 店舗登録を完了する
   - 店舗を選択する
   - 店舗情報を編集する
   - ブースを作成する
   - ブースに cast を紐づける
   - キャスト招待 URL を発行する
   - 店舗管理者招待 URL を発行する
   - ドリンクメニューを管理する
   - 通報を確認する
   - 振込先口座を設定する
   - 精算予定・履歴を確認する
8. system_admin（運営）向け操作
   - ユーザーを管理する
   - 紹介コードを管理する
   - お知らせを管理する
   - Effect を管理する
   - 店舗BANを管理する
   - 精算一覧を確認する
   - 振込 CSV を作成・確認する
   - マニュアル精算を作成する
9. 困ったとき
   - ログインできない
   - 招待 URL が使えない
   - 操作対象の店舗 / ブースが未選択
   - 権限不足で画面を開けない
   - 電話番号認証コードが届かない
   - 配信画面でカメラ / マイクが使えない

## ロール別の章構成

### customer（視聴者）

最初に読む章:

- アカウント作成
- ログイン / ログアウト
- 共通操作
- customer 向け操作

特にスクリーンショットが必要な画面:

- guest（未ログイン）のホーム
- `/sign_up` 顧客登録
- `/profile/edit` プロフィール編集
- `/phone_verification/new` 電話番号認証
- `/` ログイン後ホーム
- `/dashboard` customer 表示
- `/booths/:id` ブース詳細
- `/wallet/purchases/new` ポイント購入

### cast（配信者）

最初に読む章:

- 招待 URL からアカウント作成
- 共通操作
- cast 向け操作

特にスクリーンショットが必要な画面:

- `/cast_invitations/:token` cast 招待確認
- `/cast/sign_up?token=...` cast 登録
- `/profile/edit` 初回プロフィール編集
- `/cast/booths/:id/edit` 初回ブース編集
- `/dashboard` cast 表示
- `/cast/booths` ブース一覧
- `/cast/booths/:id` ブース情報
- `/cast/booths/:id/live` 配信画面
- `/cast/booths/:booth_id/stream_sessions` 配信履歴

第5回で撮影済み:

- `/dashboard` cast dashboard（配信者ダッシュボード）
- `/cast/booths` ブース一覧
- `/cast/booths/:id` ブース情報
- `/cast/booths/:id/edit` ブース編集
- `/cast/booths/:booth_id/stream_sessions` 配信履歴の空状態
- `/cast/booths/:id/live` standby（配信準備中）画面
- `/cast/stream_sessions/:id/pending_drink_orders` pending drink orders（未消化ドリンク）の空状態

追加撮影候補:

- 実配信開始から終了までの完全フロー
- live（配信中）/ away（席外し）への status（状態）変更
- 終了済み stream session（配信セッション）がある状態の配信履歴と配信リザルト
- customer（視聴者）からの drink order（ドリンク注文）送信と cast（配信者）による消化
- サムネ画像アップロード

### store_admin（店舗管理者）

最初に読む章:

- 店舗登録からアカウント作成
- 共通操作
- store_admin 向け操作

特にスクリーンショットが必要な画面:

- `/stores/new_registration?ref=...` 店舗登録
- `/admin/stores/:id/edit` 店舗設定編集
- `/dashboard` store_admin 表示
- `/admin/stores` 店舗選択
- `/admin/booths` ブース管理
- `/admin/booths/new` ブース作成
- `/admin/casts` キャスト一覧
- `/admin/cast_invitations` キャスト招待
- `/admin/store_admin_invitations` 店舗管理者招待
- `/admin/drink_items` ドリンクメニュー
- `/admin/cast_metrics` 配信者別数値一覧
- `/admin/comment_reports` 通報一覧
- `/admin/payout_account/edit` 振込先口座設定
- `/admin/settlements` 精算

第4回で撮影済み:

- `/dashboard` store_admin dashboard（店舗管理者ダッシュボード）
- `/admin/stores` 店舗選択
- `/admin/stores/:id/edit` 店舗情報編集
- `/admin/booths` ブース管理
- `/admin/booths/new` ブース作成
- `/admin/casts` キャスト一覧
- `/admin/cast_invitations` キャスト招待
- `/admin/store_admin_invitations` 店舗管理者招待
- `/admin/drink_items` ドリンクメニュー管理
- `/admin/cast_metrics` 配信者別数値一覧
- `/admin/comment_reports` 通報一覧
- `/admin/payout_account/edit` 振込先口座設定
- `/admin/settlements` 精算（予定・履歴）

追加撮影候補:

- 通報がある状態の `/admin/comment_reports`
- 精算履歴がある状態の `/admin/settlements`
- 売上データがある状態の `/admin/cast_metrics`
- 既存ドリンクの編集フォーム

### system_admin（運営）

最初に読む章:

- system_admin アカウントの準備方法
- 共通操作
- system_admin 向け操作

特にスクリーンショットが必要な画面:

- `/dashboard` system_admin 表示
- `/system_admin/users` ユーザー管理
- `/system_admin/users/new` ユーザー作成
- `/system_admin/referral_codes` 紹介コード管理
- `/system_admin/referral_codes/new` 紹介コード作成
- `/system_admin/notifications` お知らせ管理
- `/system_admin/effects` Effect 管理
- `/admin/stores` 店舗選択
- `/admin/store_bans` 店舗BAN
- `/system_admin/settlements` 精算一覧
- `/system_admin/settlement_exports` 振込 CSV
- `/system_admin/settlements/manual/new` マニュアル精算

## 第2回以降の Playwright 撮影候補

### 優先度A: アカウント作成から初回操作

- guest ホームから顧客登録へ進む。
- 顧客登録後、プロフィール編集へ進む。
- 店舗登録 URL から store_admin を作る。
- store_admin ダッシュボードからキャスト招待 URL を発行する。
- cast 招待 URL から cast を作り、プロフィール編集、ブース編集へ進む。
- store_admin 招待 URL から追加 store_admin を作り、招待承認後にダッシュボードへ進む。

### 優先度B: ロール別ダッシュボード

- customer ダッシュボード
- cast ダッシュボード
- store_admin ダッシュボード
- system_admin ダッシュボード
- 複数店舗 / 複数ブースがある場合の選択モーダル

### 優先度C: 通常操作

- ブース詳細と視聴 UI
- cast 配信画面（第5回で standby まで撮影済み）
- ドリンクメニューとドリンク送信
- admin ブース作成（第4回で store_admin 向け撮影済み）
- admin ドリンクメニュー管理（第4回で store_admin 向け撮影済み）
- system_admin 紹介コード管理

### 優先度D: エラー・注意点

- 招待 URL 期限切れ / 使用済み
- role（権限種別）が違う状態で招待承認しようとした場合
- 店舗 / ブースが未選択の場合
- `store_admin` が他店ブースを操作しようとした場合
- `cast` が未紐づけブースを操作しようとした場合
- 電話番号認証コードの期限切れ / 試行回数超過

## Playwright 実装前に必要なデータ

最低限:

- `system_admin` 1名
- 有効な `ReferralCode` 1件
- `Store` 1件
- `store_admin` 1名
- `cast` 1名
- `customer` 1名
- `StoreMembership`:
  - store_admin 用 `admin`
  - cast 用 `cast`
- `Booth` 1件
- `BoothCast` 1件
- `DrinkItem` 初期データ
- 撮影対象によって `Wallet` とポイント残高

注意:

- cast 招待承認やブース作成は IVS Stage（Amazon IVS の配信ルーム実体）作成を伴います。
- Playwright の前処理では、AWS を呼ばずに `ivs_stage_arn` を疑似値で用意する方針を検討する必要があります。
- 電話番号ログインの撮影では SMS の OTP（ワンタイム認証コード）取得方針が必要です。
- Stripe Checkout の実決済画面撮影は避け、アプリ内の購入プラン選択までを対象にする案が安全です。

## 根拠ファイル

- `config/routes.rb`
- `app/models/user.rb`
- `app/views/dashboard/show.html.erb`
- `app/controllers/application_controller.rb`
- `app/controllers/customers/registrations_controller.rb`
- `app/controllers/stores/registrations_controller.rb`
- `app/controllers/casts/registrations_controller.rb`
- `app/controllers/store_admins/registrations_controller.rb`
- `app/controllers/cast_invitations_controller.rb`
- `app/controllers/store_admin_invitations_controller.rb`
- `app/controllers/admin/*`
- `app/controllers/cast/*`
- `app/controllers/system_admin/*`
- `app/services/store_cast_invitations/*`
- `app/services/store_admin_invitations/*`
- `test/integration/*invitation*_test.rb`
- `test/integration/role_hierarchy_access_test.rb`
