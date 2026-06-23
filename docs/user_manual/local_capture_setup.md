# ローカル撮影基盤セットアップ

この文書は、操作マニュアル用スクリーンショットをローカルで安定して取得するための手順です。撮影用データ作成と Playwright（ブラウザ自動操作）は development / test 専用です。production（本番環境）では撮影用データ作成 task（Railsタスク）は実行できません。

## 前提

- Rails server（Railsアプリの開発サーバー）は Docker Compose で起動します。
- Playwright（ブラウザ自動操作）はホスト側の Node.js / npm から実行します。
- 対象ブラウザは Chromium のみです。
- 通常の smoke（最小確認）スクリーンショット保存先は `docs/user_manual/images/smoke/` です。
- アカウント作成フローのスクリーンショット保存先は `docs/user_manual/images/account_creation/` です。
- store_admin（店舗管理者）通常操作のスクリーンショット保存先は `docs/user_manual/images/store_admin/` です。
- 撮影用データは `manual+...@example.test`、`マニュアル撮影用...`、`MANUAL-CAPTURE-LOCAL` で識別します。

## 初回セットアップ

```bash
npm install
npm run manual:capture:install
```

`manual:capture:install` は Chromium のみをインストールします。

## Rails server の起動

既存の Docker Compose 構成に合わせます。

```bash
docker compose build
docker compose run --rm app bin/rails db:prepare
docker compose up -d
```

ブラウザからは次の URL を使います。

```text
http://127.0.0.1:3000
```

起動済みかどうかは次のコマンドで確認します。

```bash
docker compose ps
```

## 撮影用データ作成

development（開発環境）で実行します。

```bash
docker compose exec -T app bin/rails manual_capture:prepare
```

この task（Railsタスク）は idempotent（再実行可能）です。何度実行しても、固定の撮影用アカウント、店舗、ブース、紹介コード、ドリンク初期データを同じ状態へ戻します。

production（本番環境）では次のエラーで停止します。

```text
manual_capture:prepare is disabled in production
```

## Playwright smoke（最小確認）撮影

```bash
npm run manual:capture:smoke
```

保存先:

```text
docs/user_manual/images/smoke/guest_home.png
docs/user_manual/images/smoke/login.png
docs/user_manual/images/smoke/customer_dashboard.png
docs/user_manual/images/smoke/store_admin_dashboard.png
docs/user_manual/images/smoke/cast_dashboard.png
docs/user_manual/images/smoke/system_admin_dashboard.png
```

## Playwright account creation capture（アカウント作成撮影）

```bash
npm run manual:capture:accounts
```

このコマンドは次のフローを撮影します。

- customer（視聴者）の自己登録。
- store_admin（店舗管理者）の店舗登録。
- cast（配信者）の invitation（招待）登録。
- 追加 store_admin（店舗管理者）の invitation（招待）登録。

保存先:

```text
docs/user_manual/images/account_creation/customer/
docs/user_manual/images/account_creation/store_admin_registration/
docs/user_manual/images/account_creation/cast_invitation/
docs/user_manual/images/account_creation/store_admin_invitation/
```

撮影用の新規登録メールアドレスは、実行ごとに一意な `manual+account_flow_...@example.test` を使います。固定 ID で撮り直したい場合は `MANUAL_CAPTURE_RUN_ID` を指定します。

PowerShell の例:

```powershell
$env:MANUAL_CAPTURE_RUN_ID = "20260623002322"
npm run manual:capture:accounts
Remove-Item Env:\MANUAL_CAPTURE_RUN_ID
```

同じ `MANUAL_CAPTURE_RUN_ID` を同じ database（データベース）に対して再実行すると、メールアドレス重複で失敗する可能性があります。通常は環境変数を指定せず、毎回一意 ID を自動生成してください。

## Playwright store_admin capture（店舗管理者通常操作撮影）

```bash
npm run manual:capture:store_admin
```

このコマンドは store_admin（店舗管理者）でログインし、次の画面を撮影します。

- `/dashboard` dashboard（ダッシュボード）
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

保存先:

```text
docs/user_manual/images/store_admin/dashboard/
docs/user_manual/images/store_admin/stores/
docs/user_manual/images/store_admin/booths/
docs/user_manual/images/store_admin/casts/
docs/user_manual/images/store_admin/invitations/
docs/user_manual/images/store_admin/drink_items/
docs/user_manual/images/store_admin/metrics/
docs/user_manual/images/store_admin/comment_reports/
docs/user_manual/images/store_admin/payout_account/
docs/user_manual/images/store_admin/settlements/
```

store_admin capture（店舗管理者通常操作撮影）は、長い管理画面を説明しやすくするため、既定で fullPage（ページ全体撮影）を使います。表示範囲だけを撮りたい場合は `MANUAL_CAPTURE_FULL_PAGE=0` を指定してください。

PowerShell の例:

```powershell
$env:MANUAL_CAPTURE_FULL_PAGE = "0"
npm run manual:capture:store_admin
Remove-Item Env:\MANUAL_CAPTURE_FULL_PAGE
```

事前に `docker compose exec -T app bin/rails manual_capture:prepare` を実行してください。店舗選択画面を撮るため、この task（Railsタスク）は `マニュアル撮影用店舗` と `マニュアル撮影用サブ店舗` の2店舗を作成します。

## オプション

別 URL に向けたい場合は `MANUAL_CAPTURE_BASE_URL` を指定します。

```bash
MANUAL_CAPTURE_BASE_URL=http://127.0.0.1:3000 npm run manual:capture:smoke
```

PowerShell の例:

```powershell
$env:MANUAL_CAPTURE_BASE_URL = "http://127.0.0.1:3000"
npm run manual:capture:smoke
Remove-Item Env:\MANUAL_CAPTURE_BASE_URL
```

ページ全体を撮影したい場合は `MANUAL_CAPTURE_FULL_PAGE=1` を指定します。

```powershell
$env:MANUAL_CAPTURE_FULL_PAGE = "1"
npm run manual:capture:accounts
Remove-Item Env:\MANUAL_CAPTURE_FULL_PAGE
```

## 外部サービス依存の回避方針

### IVS Stage（Amazon IVS の配信ルーム実体）

固定撮影用データでは `manual_capture:prepare` が `Booth#ivs_stage_arn` に疑似値を設定します。

```text
arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local
```

cast invitation（配信者招待）承認で新しい Booth（ブース）を作る場合は、`Booths::ProvisionIvsStageService` が呼ばれます。production（本番環境）以外で、店舗名に `manual` または `マニュアル撮影用` を含むマニュアル撮影データだけ、AWS（Amazon Web Services）を呼ばずに次の形式の疑似 ARN を保存します。

```text
arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local-booth-<booth_id>
```

production（本番環境）ではこの疑似化分岐は無効です。通常の店舗名に対しても自動では有効になりません。開発・検証で明示的に疑似化したい場合のみ `MANUAL_CAPTURE_FAKE_IVS=1` を使えますが、本番では無効です。

store_admin capture（店舗管理者通常操作撮影）のブース作成もこの方針に従います。

### SMS（ショートメッセージ）

`Sms::Sender` は development / test では既定で mock（ログ出力のみ）です。今回の撮影では SMS OTP（ワンタイム認証コード）入力フローは扱いません。固定撮影用ユーザーには `phone_number` と `phone_verified_at` を設定し、電話番号認証済みの表示確認だけができる状態にしています。

### Stripe（決済）

実決済は行いません。今回の撮影では購入完了や Stripe Checkout（Stripe の決済画面）への遷移は対象外です。customer（視聴者）用の `Wallet` は撮影用 task（Railsタスク）で固定ポイントを付与します。

### Banuba / DeepAR（画面加工）

今回の撮影では cast（配信者）の配信画面、カメラ、画面加工画面にはアクセスしません。token / license が未設定でも smoke（最小確認）と account creation capture（アカウント作成撮影）は失敗しない構成です。

## 関連ファイル

- `lib/tasks/manual_capture.rake`
- `playwright.config.js`
- `tests/manual_capture/smoke.spec.js`
- `tests/manual_capture/account_creation.spec.js`
- `tests/manual_capture/store_admin.spec.js`
- `docs/user_manual/manual_accounts.md`
- `docs/user_manual/capture_progress.md`
- `docs/user_manual/account_creation_capture.md`
- `docs/user_manual/account_creation_manual_draft.md`
- `docs/user_manual/store_admin_capture.md`
- `docs/user_manual/store_admin_manual_draft.md`
