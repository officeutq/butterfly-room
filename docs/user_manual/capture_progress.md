# 撮影進捗

この文書は、操作マニュアル用スクリーンショット取得の進捗メモです。第2回作業では、全画面撮影ではなく、ローカル撮影基盤の smoke（最小確認）だけを実施しました。

## 今回取得できたスクリーンショット

| ファイル | 対象 | 状態 |
| --- | --- | --- |
| `docs/user_manual/images/smoke/guest_home.png` | guest（未ログイン）ホーム | 取得済み |
| `docs/user_manual/images/smoke/login.png` | ログイン画面 | 取得済み |
| `docs/user_manual/images/smoke/customer_dashboard.png` | customer（視聴者）ログイン後 `/dashboard` | 取得済み |
| `docs/user_manual/images/smoke/store_admin_dashboard.png` | store_admin（店舗管理者）ログイン後 `/dashboard` | 取得済み |
| `docs/user_manual/images/smoke/cast_dashboard.png` | cast（配信者）ログイン後 `/dashboard` | 取得済み |
| `docs/user_manual/images/smoke/system_admin_dashboard.png` | system_admin（運営）ログイン後 `/dashboard` | 取得済み |

## 実行コマンド

```bash
docker compose exec -T app bin/rails manual_capture:prepare
npm run manual:capture:smoke
```

## 取得できなかったもの

今回の smoke（最小確認）範囲ではありません。

- アカウント作成フロー全体
- cast（配信者）の配信開始から終了まで
- customer（視聴者）の配信視聴、コメント、ドリンク送信
- Stripe（決済）の購入完了
- SMS OTP（ショートメッセージのワンタイム認証コード）入力
- Banuba / DeepAR（画面加工）を使う配信画面
- Google Docs 連携

## 次回撮影すべき画面

`docs/user_manual/manual_outline.md` の優先度A/Bを元に、次は次の画面を追加撮影します。

1. customer（視聴者）
   - `/sign_up`
   - `/profile/edit`
   - `/phone_verification/new`
   - `/booths/:id`
   - `/wallet/purchases/new`
2. store_admin（店舗管理者）
   - `/stores/new_registration?ref=...`
   - `/admin/stores/:id/edit`
   - `/admin/booths`
   - `/admin/casts`
   - `/admin/cast_invitations`
   - `/admin/drink_items`
3. cast（配信者）
   - `/cast/booths`
   - `/cast/booths/:id`
   - `/cast/booths/:id/edit`
   - `/cast/booths/:id/live`
4. system_admin（運営）
   - `/system_admin/users`
   - `/system_admin/referral_codes`
   - `/system_admin/notifications`
   - `/system_admin/effects`

## 未確認点

- 今回の smoke 撮影は desktop（デスクトップ）相当の Chromium のみです。mobile（スマートフォン幅）撮影は未実施です。
- 配信画面はカメラ / マイク / IVS / Banuba / DeepAR の依存があるため、別途撮影方針が必要です。
- Stripe Checkout（Stripeの決済画面）は実決済を避けるため、購入完了まで撮影するかは未確定です。
- SMS OTP の完全撮影は、mock（ログ出力）から OTP を取得する方法を決めてから実施します。
- smoke 撮影は既定で viewport（表示範囲）撮影です。ページ全体が必要な場合は `MANUAL_CAPTURE_FULL_PAGE=1` を指定して再撮影します。
