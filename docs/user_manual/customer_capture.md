# customer 通常操作撮影結果

この文書は、第6回作業で取得した customer（視聴者）向け通常操作スクリーンショットの撮影記録です。撮影は development（開発環境）で実行し、production（本番環境）の挙動は変更していません。

## 撮影コマンド

```bash
docker compose exec -T app bin/rails manual_capture:prepare
npm run manual:capture:customer
```

`npm run manual:capture:customer` は既定で `docker compose exec -T app bin/rails manual_capture:prepare_customer_viewer` を実行し、customer（視聴者）撮影用の live（配信中）サブブースを準備します。Docker Compose 以外の起動方法を使う場合は、事前に task（Railsタスク）を実行したうえで `MANUAL_CAPTURE_SKIP_CUSTOMER_VIEWER_PREPARE=1` を指定してください。

customer（視聴者）は `manual_capture:prepare` が作成する `manual+customer@example.test` を使用しました。固定パスワードは内部撮影用情報のため、読者向けマニュアル本文には記載しません。

## 撮影した画面と実際の遷移先

| 対象 | 開始 URL / 操作 | 実際の遷移・結果 |
| --- | --- | --- |
| dashboard（ダッシュボード） | `/dashboard` | customer（視聴者）向けカードとしてプロフィール編集、電話番号認証を表示 |
| プロフィール編集 | `/profile/edit` | 表示名・自己紹介を入力し、更新後 `/` へ遷移 |
| 電話番号認証 | `/phone_verification` | 認証済み電話番号と変更用フォームを表示。SMS（ショートメッセージ）送信は未実行 |
| ホーム ブース一覧 | `/?mode=booths` | booth（ブース）カード一覧を表示 |
| ホーム ブース検索 | `/?mode=booths&q=サブ` | キーワードに一致する booth（ブース）を表示 |
| ホーム 店舗一覧 | `/?mode=stores` | Store（店舗）カード一覧を表示 |
| ホーム ユーザー一覧 | `/?mode=users` | cast（配信者）と store_admin（店舗管理者）ユーザーを表示 |
| 店舗詳細 | Store（店舗）カードから遷移 | `/stores/:id` に遷移し、店舗情報と booth（ブース）一覧を表示 |
| cast（配信者）プロフィール | ユーザーカードから遷移 | `/users/:id` に遷移し、プロフィールと関連 booth（ブース）を表示 |
| offline（オフライン）ブース詳細 | `マニュアル撮影用ブース` を開く | `/booths/:id` で待機中の booth（ブース）詳細を表示 |
| live（配信中）視聴画面 | `マニュアル撮影用サブブース` を開く | `/booths/:id` で viewer（視聴者）向け live UI（配信視聴画面）を表示 |
| コメント入力 | live 視聴画面 | コメント入力欄に入力例を表示。送信は未実行 |
| ドリンクメニュー | live 視聴画面のドリンクボタン | ドリンク一覧を表示。ドリンク送信は未実行 |
| ポイント購入 | ヘッダーのポイント残高 | `/wallet/purchases/new` を modal（モーダル）で表示。Stripe（決済）遷移は未実行 |
| お気に入り一覧 | `/favorites/booths`, `/favorites/stores`, `/favorites/users` | 撮影用のお気に入り booth / store / user を表示 |

## 保存したスクリーンショット

### dashboard（ダッシュボード）

- `images/customer/dashboard/01_dashboard.png`

### ホーム検索

- `images/customer/home/01_booths_index.png`
- `images/customer/home/02_booth_search.png`
- `images/customer/home/03_stores_index.png`
- `images/customer/home/04_users_index.png`

### 店舗・ユーザー・ブース詳細

- `images/customer/stores/01_show.png`
- `images/customer/users/01_cast_show.png`
- `images/customer/booths/01_offline_show.png`

### live（配信中）視聴画面

- `images/customer/live/01_live_viewer.png`
- `images/customer/live/02_comment_filled.png`
- `images/customer/live/03_drink_menu.png`

### プロフィール・電話番号・ポイント購入

- `images/customer/profile/01_edit_form.png`
- `images/customer/profile/02_edit_filled.png`
- `images/customer/profile/03_after_update_home.png`
- `images/customer/phone/01_new_form.png`
- `images/customer/phone/02_new_filled.png`
- `images/customer/wallet/01_purchase_modal.png`

### お気に入り

- `images/customer/favorites/01_booths_index.png`
- `images/customer/favorites/02_stores_index.png`
- `images/customer/favorites/03_users_index.png`

## 実行しなかった危険操作

- SMS OTP（ショートメッセージのワンタイム認証コード）送信・入力は実行していません。
- Stripe Checkout（Stripe の決済画面）への遷移と購入完了は実行していません。
- comment（コメント）送信は実行していません。
- drink order（ドリンク注文）送信は実行していません。
- 実 IVS join（Amazon IVS への参加）は実行していません。
- cast（配信者）側の配信開始・終了、ドリンク消化は実行していません。

## 外部サービス依存の扱い

- `manual_capture:prepare_customer_viewer` は `マニュアル撮影用サブブース` に疑似 `ivs_stage_arn` を持つ stream session（配信セッション）を紐づけ、DB（データベース）上だけで live（配信中）状態を作ります。
- Playwright（ブラウザ自動操作）では `https://web-broadcast.live-video.net/.../amazon-ivs-web-broadcast.js` を fake（代替応答）し、実 IVS SDK 読み込みを行いません。
- Playwright（ブラウザ自動操作）では `/stream_sessions/:id/ivs_participant_tokens` も fake（代替応答）し、`Ivs::CreateParticipantTokenService` 経由の AWS（Amazon Web Services）呼び出しへ進みません。
- ポイント購入 modal（モーダル）は表示だけに留め、`Wallets::CreateCheckoutService` の Stripe 呼び出しは実行していません。
- 電話番号認証画面は表示と入力例までに留め、`PhoneVerifications::IssueOtpService` による SMS 送信は実行していません。

## 確認した主な実コード

- `config/routes.rb`
- `app/controllers/dashboard_controller.rb`
- `app/controllers/home_controller.rb`
- `app/controllers/booths_controller.rb`
- `app/controllers/stores_controller.rb`
- `app/controllers/users_controller.rb`
- `app/controllers/profiles_controller.rb`
- `app/controllers/phone_verifications_controller.rb`
- `app/controllers/favorites/booths_controller.rb`
- `app/controllers/favorites/stores_controller.rb`
- `app/controllers/favorites/users_controller.rb`
- `app/controllers/stream_sessions/comments_controller.rb`
- `app/controllers/stream_sessions/drink_orders_controller.rb`
- `app/controllers/stream_sessions/ivs_participant_tokens_controller.rb`
- `app/controllers/wallet/purchases_controller.rb`
- `app/views/dashboard/show.html.erb`
- `app/views/home/show.html.erb`
- `app/views/home/_header_subnav.html.erb`
- `app/views/booths/show.html.erb`
- `app/views/booths/_waiting_state.html.erb`
- `app/views/booths/_stream_state.html.erb`
- `app/views/stream_sessions/_ivs_viewer.html.erb`
- `app/views/stream_sessions/comments/_form.html.erb`
- `app/views/booths/_drink_menu.html.erb`
- `app/views/stores/show.html.erb`
- `app/views/users/show.html.erb`
- `app/views/profiles/edit.html.erb`
- `app/views/phone_verifications/new.html.erb`
- `app/views/wallet/purchases/new.html.erb`
- `app/javascript/controllers/ivs_viewer_controller.js`
- `app/javascript/controllers/viewer_page_controller.js`
- `app/javascript/controllers/viewer_drink_panel_controller.js`
- `app/javascript/controllers/comment_panel_controller.js`
- `app/services/authorization/viewer_policy.rb`
- `app/services/stream_sessions/comments/create_service.rb`
- `app/services/drink_orders/create_service.rb`
- `app/services/wallets/create_checkout_service.rb`
- `test/integration/home_search_test.rb`
- `test/integration/favorites_toggle_test.rb`
- `test/integration/favorites_index_test.rb`
- `test/integration/store_show_test.rb`
- `test/integration/stream_session_drink_orders_test.rb`
- `test/integration/wallet/purchases_test.rb`

## 未確認点

- comment（コメント）送信後の表示更新。
- drink order（ドリンク注文）送信後の Wallet（ポイント残高）・未消化ドリンク表示。
- Stripe Checkout（Stripe の決済画面）遷移後の購入完了。
- SMS OTP（ショートメッセージのワンタイム認証コード）発行・入力。
- mobile（スマートフォン幅）での customer（視聴者）操作。
- 実 IVS join を伴う映像視聴。
