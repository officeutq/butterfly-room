# customer（視聴者）向け操作マニュアル ドラフト

この章では、customer（視聴者）がログイン後に行う基本操作を説明します。アカウント作成は「アカウント作成」章の customer（視聴者）自己登録を参照してください。

## dashboard（ダッシュボード）を確認する

ログイン後、dashboard（ダッシュボード）には customer（視聴者）が使う画面へのカードが表示されます。

![customer dashboard](images/customer/dashboard/01_dashboard.png)

主なカードは次のとおりです。

- 「プロフィール編集」: 表示名、自己紹介、プロフィール画像を編集します。
- 「電話番号認証」: 電話番号の認証状況を確認し、必要に応じて認証します。

## プロフィールを編集する

1. dashboard（ダッシュボード）で「プロフィール編集」を開きます。
2. 「表示名」と「自己紹介（bio）」を入力します。
3. 必要に応じてプロフィール画像を選択します。
4. 「更新する」を押します。

![プロフィール編集フォーム](images/customer/profile/01_edit_form.png)

入力済みの例です。

![プロフィール編集入力済み](images/customer/profile/02_edit_filled.png)

更新が完了するとホームへ戻り、「プロフィールを更新しました」と表示されます。

![プロフィール更新後](images/customer/profile/03_after_update_home.png)

TODO: プロフィール画像アップロードの具体的な操作と推奨画像サイズは、別途撮影して追記します。

## 電話番号を認証する

1. dashboard（ダッシュボード）で「電話番号認証」を開きます。
2. 現在の認証状況を確認します。
3. 新しい電話番号を登録する場合は、電話番号を入力します。
4. 「認証コードを送信」を押します。
5. SMS（ショートメッセージ）で届いた認証コードを入力します。

![電話番号認証フォーム](images/customer/phone/01_new_form.png)

入力済みの例です。

![電話番号認証入力済み](images/customer/phone/02_new_filled.png)

TODO: SMS OTP（ショートメッセージのワンタイム認証コード）送信後の認証コード入力画面とエラー表示は、別途撮影して追記します。

## ホームで booth（ブース）を探す

1. フッターの「ホーム」を開きます。
2. 上部の切り替えで「ブース」を選択します。
3. 必要に応じてキーワードを入力して検索します。
4. 見たい booth（ブース）の名前または画像を押します。

![ブース一覧](images/customer/home/01_booths_index.png)

キーワード検索の例です。

![ブース検索](images/customer/home/02_booth_search.png)

booth（ブース）カードには、配信状態、ブース名、所属 cast（配信者）、所属店舗が表示されます。星アイコンからお気に入り登録できます。

## Store（店舗）を探す

1. ホーム上部の切り替えで「店舗」を選択します。
2. 店舗カードを確認します。
3. 店舗名または画像を押すと店舗詳細を開けます。

![店舗一覧](images/customer/home/03_stores_index.png)

店舗詳細では、地域、業態、住所、電話番号、営業時間、説明文、所属 booth（ブース）を確認できます。

![店舗詳細](images/customer/stores/01_show.png)

## cast（配信者）を探す

1. ホーム上部の切り替えで「ユーザー」を選択します。
2. cast（配信者）または store_admin（店舗管理者）のカードを確認します。
3. ユーザー名または画像を押すとプロフィール詳細を開けます。

![ユーザー一覧](images/customer/home/04_users_index.png)

cast（配信者）プロフィールでは、自己紹介と関連 booth（ブース）を確認できます。

![castプロフィール](images/customer/users/01_cast_show.png)

## offline（オフライン）の booth（ブース）詳細を見る

配信中ではない booth（ブース）を開くと、ブース名、cast（配信者）、店舗、説明文が表示されます。

![offlineブース詳細](images/customer/booths/01_offline_show.png)

星アイコンから booth（ブース）、店舗、cast（配信者）をお気に入り登録できます。

## live（配信中）を視聴する

配信中の booth（ブース）を開くと、viewer（視聴者）向けの live UI（配信視聴画面）が表示されます。

![live視聴画面](images/customer/live/01_live_viewer.png)

画面上部には配信状態、cast（配信者）名、配信タイトルが表示されます。画面下部にはコメント入力欄、ドリンクメニュー、ミュート切替があります。

TODO: 実映像が表示されている状態のスクリーンショットは、IVS（Amazon IVS の配信基盤）接続方法を確認してから追記します。

## コメントする

1. live（配信中）視聴画面のコメント欄を選択します。
2. コメントを入力します。
3. 「送信」を押します。

![コメント入力済み](images/customer/live/02_comment_filled.png)

TODO: コメント送信後にコメント欄へ反映される状態は、別途撮影して追記します。

## ドリンクを送る

1. live（配信中）視聴画面でドリンクアイコンを押します。
2. ドリンクメニューを確認します。
3. 送りたいドリンクを選択します。

![ドリンクメニュー](images/customer/live/03_drink_menu.png)

ドリンク送信にはポイント残高が必要です。送信したドリンクは cast（配信者）側で pending drink orders（未消化ドリンク）として表示され、cast（配信者）が消化すると売上に反映されます。

TODO: ドリンク送信後のポイント残高、未消化ドリンク表示、cast（配信者）側の消化操作は別途撮影して追記します。

## ポイントを購入する

1. 画面上部のポイント残高を押します。
2. ポイント購入 modal（モーダル）で購入プランを選択します。
3. 「購入する」を押します。
4. Stripe Checkout（Stripe の決済画面）で支払いを完了します。

![ポイント購入モーダル](images/customer/wallet/01_purchase_modal.png)

TODO: Stripe Checkout（Stripe の決済画面）以降の購入完了フローは、実決済を避ける検証方法を確認してから追記します。

## お気に入りを確認する

フッターの「お気に入り」を開くと、お気に入り登録した booth（ブース）、Store（店舗）、user（ユーザー）を確認できます。

![お気に入りブース](images/customer/favorites/01_booths_index.png)

上部の切り替えから、店舗とユーザーのお気に入りも確認できます。

![お気に入り店舗](images/customer/favorites/02_stores_index.png)

![お気に入りユーザー](images/customer/favorites/03_users_index.png)

TODO: お気に入りの追加・解除を実際に操作する手順と、一覧から検索する手順を別途追記します。

## 困ったとき

TODO: 次のケースは、エラー画面や注意表示を撮影してから追記します。

- booth（ブース）が offline（オフライン）でコメント・ドリンク送信できない。
- ポイント残高が不足している。
- 店舗BANにより booth（ブース）や Store（店舗）を開けない。
- SMS OTP（ショートメッセージのワンタイム認証コード）が届かない。
- Stripe Checkout（Stripe の決済画面）で支払いが完了しない。
- 映像が再生されない、または音声が出ない。
