# 撮影用アカウント一覧

この文書は、操作マニュアル用スクリーンショット取得に使うローカル撮影用アカウントの一覧です。development / test 専用で、production（本番環境）では作成しません。

## 作成コマンド

```bash
docker compose exec -T app bin/rails manual_capture:prepare
```

customer（視聴者）通常操作撮影で live（配信中）視聴画面を撮る場合は、次の development / test 専用 task（Railsタスク）も使います。

```bash
docker compose exec -T app bin/rails manual_capture:prepare_customer_viewer
```

## 共通パスワード

```text
ManualCapture123!
```

## アカウント一覧

| role（権限種別） | 画面上の説明 | メールアドレス | パスワード | 電話番号 | 電話番号認証 |
| --- | --- | --- | --- | --- | --- |
| `system_admin` | 運営 | `manual+system_admin@example.test` | `ManualCapture123!` | `+819000000001` | 認証済み |
| `store_admin` | 店舗管理者 | `manual+store_admin@example.test` | `ManualCapture123!` | `+819000000002` | 認証済み |
| `cast` | 配信者 | `manual+cast@example.test` | `ManualCapture123!` | `+819000000003` | 認証済み |
| `customer` | 視聴者 | `manual+customer@example.test` | `ManualCapture123!` | `+819000000004` | 認証済み |

## 関連データ

| 種別 | 値 | 補足 |
| --- | --- | --- |
| ReferralCode（紹介コード） | `MANUAL-CAPTURE-LOCAL` | 有効化済み、期限は task 実行時から1年後 |
| Store（店舗） | `マニュアル撮影用店舗` | `store_admin` が admin（管理者）として所属 |
| Store（店舗） | `マニュアル撮影用サブ店舗` | 店舗選択画面の撮影用。`store_admin` が admin（管理者）として所属 |
| Booth（ブース） | `マニュアル撮影用ブース` | `cast` が `BoothCast` で紐づく |
| Booth（ブース） | `マニュアル撮影用サブブース` | cast（配信者）のブース一覧・current booth（現在選択中のブース）撮影用。`cast` が `BoothCast` で紐づく |
| IVS Stage ARN | `arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local` | AWS を呼ばない疑似値 |
| IVS Stage ARN | `arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local-secondary` | サブブース用の疑似値 |
| Wallet（ポイント残高） | `100000pt` | `customer` に付与 |
| DrinkItem（ドリンクメニュー） | `config/default_drink_items.yml` の development 設定 | `マニュアル撮影用店舗` に作成 |
| StreamSession（配信セッション） | `マニュアル撮影用ライブ配信` | `manual_capture:prepare_customer_viewer` で `マニュアル撮影用サブブース` に作成 |
| FavoriteBooth / FavoriteStore / FavoriteUser（お気に入り） | サブブース / 店舗 / cast | customer（視聴者）通常操作撮影用 |

## 作成される関連レコード

- `User`: 4件
- `ReferralCode`: 1件
- `Store`: 2件
- `StoreMembership`: store_admin 用 `admin` 2件、cast 用 `cast` 1件
- `Booth`: 2件
- `BoothCast`: 2件
- `DrinkItem`: 6件
- `Wallet`: customer 用 1件
- `WalletTransaction`: customer 用 adjustment（調整）1件

`manual_capture:prepare_customer_viewer` を実行した場合は、上記に加えて次を作成または更新します。

- `StreamSession`: `マニュアル撮影用サブブース` 用 live（配信中）1件
- `Comment`: customer（視聴者）撮影用の固定コメント1件
- `FavoriteBooth`: customer 用 1件
- `FavoriteStore`: customer 用 1件
- `FavoriteUser`: customer 用 1件

`manual:capture:system_admin` を実行した場合は、固定 task（Railsタスク）ではなく UI 操作で次の撮影用データを作成します。`<run_id>` は通常、実行時に自動採番される一意な値です。

- `User`: `manual+system_admin_capture_user_<run_id>@example.test`
- `ReferralCode`: `MANUAL-SYSTEM-ADMIN-<run_id>`
- `Notification`: `マニュアル撮影用お知らせ <run_id>`
- `Effect`: `manual_system_admin_<run_id>`

これらは system_admin（運営）画面の作成・保存後表示を撮るための development / test 専用データです。同じ `MANUAL_CAPTURE_RUN_ID` を同じ database（データベース）で再利用すると、email（メールアドレス）、code（コード）、key（一意キー）の uniqueness（一意制約）で失敗する可能性があります。

## 注意点

- このアカウント一覧はローカル撮影用の固定値です。実運用ユーザーの手順として記載しないでください。
- `cast` は招待承認フローを通さず、撮影用 task で店舗所属・ブース紐づけを作ります。IVS Stage（Amazon IVS の配信ルーム実体）作成を避けるためです。
- `store_admin` は店舗登録画面を通さず、撮影用 task で Store（店舗）と StoreMembership（店舗所属）を作ります。
- `customer` の Wallet（ポイント残高）は Stripe（決済）を通さず、撮影用 task で固定値を設定します。
- `manual_capture:prepare_customer_viewer` は `manual_capture:prepare` を内部で呼ぶため、既存の固定撮影用データを整えたうえで `マニュアル撮影用サブブース` だけを live（配信中）にします。
- 既存の production（本番環境）向け seed（初期データ投入処理）とは別物です。
