# ローカル撮影基盤セットアップ

この文書は、操作マニュアル用スクリーンショットをローカルで安定して取得するための手順です。撮影用データ作成と Playwright（ブラウザ自動操作）は development / test 専用です。production（本番環境）では撮影用データ作成 task（Railsタスク）は実行できません。

## 前提

- Rails server（Railsアプリの開発サーバー）は既存の Docker Compose を使います。
- Playwright（ブラウザ自動操作）はホスト側の Node.js / npm から実行します。
- 対象ブラウザは Chromium に限定します。
- スクリーンショット保存先は `docs/user_manual/images/smoke/` です。
- 撮影用データは `manual+...@example.test`、`マニュアル撮影用...`、`MANUAL-CAPTURE-LOCAL` で識別します。

## 初回セットアップ

```bash
npm install
npm run manual:capture:install
```

`manual:capture:install` は Chromium のみをインストールします。

## Rails server の起動

既存 README の Docker Compose 構成に合わせます。

```bash
docker compose build
docker compose run --rm app bin/rails db:prepare
docker compose up -d
```

ブラウザからは次の URL を使います。

```text
http://127.0.0.1:3000
```

既に起動済みの場合は、次の確認だけで十分です。

```bash
docker compose ps
```

## 撮影用データ作成

development（開発環境）で実行します。

```bash
docker compose exec -T app bin/rails manual_capture:prepare
```

この task（Railsタスク）は idempotent（再実行可能）です。何度実行しても、同じメールアドレス・店舗名・ブース名の撮影用データを作り直します。

production（本番環境）では次のエラーで停止します。

```text
manual_capture:prepare is disabled in production
```

## Playwright smoke 撮影

```bash
npm run manual:capture:smoke
```

既定では viewport（表示範囲）だけを撮影します。ページ全体を撮影したい場合は `MANUAL_CAPTURE_FULL_PAGE=1` を指定します。

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

## スクリーンショット保存先

```text
docs/user_manual/images/smoke/guest_home.png
docs/user_manual/images/smoke/login.png
docs/user_manual/images/smoke/customer_dashboard.png
docs/user_manual/images/smoke/store_admin_dashboard.png
docs/user_manual/images/smoke/cast_dashboard.png
docs/user_manual/images/smoke/system_admin_dashboard.png
```

## 外部サービス依存の回避方針

### IVS Stage（Amazon IVS の配信ルーム実体）

撮影用データ作成では `Booths::ProvisionIvsStageService` を呼びません。`Booth#ivs_stage_arn` に次の疑似値を直接設定します。

```text
arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local
```

これにより AWS（Amazon Web Services）への実リクエストを避けます。production（本番環境）の挙動は変更していません。

### SMS（ショートメッセージ）

`Sms::Sender` は development / test では既定で mock（ログ出力のみ）です。今回の smoke 撮影では OTP（ワンタイム認証コード）送信フローは扱いません。撮影用ユーザーには `phone_number` と `phone_verified_at` を設定し、電話番号認証済みの表示確認だけできる状態にします。

### Stripe（決済）

実決済は行いません。今回の smoke 撮影では購入完了や Stripe Checkout（Stripeの決済画面）への遷移は対象外です。customer（視聴者）用の `Wallet` は撮影用 task で固定ポイントを付与します。

### Banuba / DeepAR（画面加工）

今回の smoke 撮影では cast（配信者）の配信画面、カメラ、画面加工画面にはアクセスしません。token / license が未設定でも smoke 撮影基盤は失敗しない構成です。

## 関連ファイル

- `lib/tasks/manual_capture.rake`
- `playwright.config.js`
- `tests/manual_capture/smoke.spec.js`
- `docs/user_manual/manual_accounts.md`
- `docs/user_manual/capture_progress.md`
