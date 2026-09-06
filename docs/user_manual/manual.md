# Butterflyve 操作マニュアル

対象: customer（視聴者）/ cast（配信者）/ store_admin（店舗管理者）/ system_admin（運営）

本書は Butterflyve の基本操作をまとめた操作マニュアルです。一部の手順には、今後の運用確認や追加撮影が必要な TODO が残っています。

## はじめに

Butterflyve は、Store（店舗）と booth（ブース）を通じて cast（配信者）が配信し、customer（視聴者）が視聴、コメント、ポイント購入、ドリンク送信などを行うためのアプリです。

このマニュアルでは、利用者の role（権限種別）ごとに操作を分けて説明します。

- customer（視聴者）: 配信を探す、視聴する、コメントする、ドリンクを送る、ポイントを購入する利用者です。
- cast（配信者）: booth（ブース）に紐づいて配信し、プロフィールやブース情報、配信履歴、未消化ドリンクを管理する利用者です。
- store_admin（店舗管理者）: Store（店舗）、booth（ブース）、cast（配信者）、ドリンクメニュー、通報、振込先口座、精算情報を管理する利用者です。
- system_admin（運営）: ユーザー、紹介コード、お知らせ、Effect（配信画面のエフェクト）、店舗BAN、精算、振込CSVなどを管理する内部運用向けの利用者です。

system_admin（運営）向け章は内部運用向けです。通常の店舗や視聴者向けには共有しない前提で扱ってください。

## このマニュアルの読み方

最初に「アカウント作成」と「共通操作」を確認し、自分の role（権限種別）に合う章へ進んでください。

- customer（視聴者）は「customer（視聴者）向け操作」を確認してください。
- cast（配信者）は「cast（配信者）向け操作」を確認してください。
- store_admin（店舗管理者）は「store_admin（店舗管理者）向け操作」を確認してください。
- system_admin（運営）は「system_admin（運営）向け操作」を確認してください。

TODO は、今後の確認や運用ルール確定後に追記する予定の内容です。

# アカウント作成

Butterflyve のアカウント作成方法は role（権限種別）によって異なります。

TODO: 招待 URL や紹介コードを受け取る具体的な案内文は、運用ルールに合わせて追記してください。

## customer（視聴者）アカウントを作成する

customer（視聴者）は、アカウント作成画面から自分で登録できます。

1. アカウント作成画面を開きます。

![customer アカウント作成フォーム](images/account_creation/customer/01_signup_form.png)

2. メールアドレス、パスワード、確認用パスワードを入力します。

![customer アカウント作成フォーム入力済み](images/account_creation/customer/02_signup_filled.png)

3. 登録ボタンを押します。
4. 登録が完了すると、プロフィール編集画面へ移動します。表示名や自己紹介を必要に応じて設定します。

![customer 登録後のプロフィール編集](images/account_creation/customer/03_after_signup_profile_edit.png)

TODO: プロフィール編集後に最初に案内する画面を、運用上の推奨導線に合わせて確定してください。

## store_admin（店舗管理者）として店舗を登録する

store_admin（店舗管理者）は、店舗登録 URL から店舗とアカウントを同時に作成します。

1. 受け取った店舗登録 URL を開きます。URL には referral code（紹介コード）が含まれる場合があります。

![店舗登録フォーム](images/account_creation/store_admin_registration/01_registration_form.png)

2. 店舗名、メールアドレス、パスワード、確認用パスワードを入力します。紹介コードを持っている場合は紹介コードも入力します。

![店舗登録フォーム入力済み](images/account_creation/store_admin_registration/02_registration_filled.png)

3. 登録ボタンを押します。
4. 店舗とアカウントが作成されると、自動的にログインして初回店舗設定画面へ移動します。この時点では店舗はまだ公開されていません。
5. 店舗名、紹介文、エリア、業種、住所、連絡先、営業時間、Webサイト、SNSを確認・入力します。必要に応じて店舗画像を選択・クロップし、「保存して公開」を押します。追加の必須項目はないため、店舗名だけでも保存できます。
6. 正常に保存されると「店舗情報の登録・公開が完了しました」と表示されます。エラーが表示された場合は、初回店舗設定画面の入力内容や画像を確認してから再度保存してください。
7. 「ダッシュボードへ進む」を押します。ダッシュボードでは、最初にcast（配信者）の招待を案内するオンボーディングが始まります。

TODO: 初回店舗設定、公開完了、ダッシュボードの新しい3画面を撮影し、旧`03_after_registration_store_edit.png`から差し替えてください。

初回店舗設定から離脱すると、同じ初回フローを自動復元しません。通常の店舗設定から情報の編集・公開はできます。

TODO: 紹介コードの配布元、期限、入力できない場合の問い合わせ先を追記してください。

## cast（配信者）招待 URL を発行する

cast（配信者）は、店舗から発行された invitation（招待）URL を使ってアカウントを作成します。まず store_admin（店舗管理者）が招待 URL を発行します。

1. store_admin（店舗管理者）でログインし、cast invitation（配信者招待）画面を開きます。

![cast 招待発行フォーム](images/account_creation/cast_invitation/01_admin_invitation_form.png)

2. 必要に応じてメモを入力します。

![cast 招待メモ入力済み](images/account_creation/cast_invitation/02_admin_invitation_filled.png)

3. 招待 URL を発行します。発行された URL を、招待したい cast（配信者）へ共有します。

![cast 招待 URL 発行後](images/account_creation/cast_invitation/03_admin_invitation_issued.png)

TODO: 招待 URL の共有方法、再発行、期限切れ時の案内を運用ルールに合わせて追記してください。

## cast（配信者）アカウントを作成する

1. 受け取った cast invitation（配信者招待）URL を開きます。招待内容を確認します。

![cast 招待確認画面](images/account_creation/cast_invitation/04_invitation_guest.png)

2. 新規 cast アカウント作成へ進みます。

![cast アカウント作成フォーム](images/account_creation/cast_invitation/05_signup_form.png)

3. メールアドレス、パスワード、確認用パスワードを入力します。

![cast アカウント作成フォーム入力済み](images/account_creation/cast_invitation/06_signup_filled.png)

4. 登録ボタンを押します。登録後、招待確認画面へ戻ります。

![cast 登録後の招待確認](images/account_creation/cast_invitation/07_after_signup_invitation.png)

5. 招待を承認します。
6. 承認後、プロフィール編集画面へ移動します。表示名や自己紹介を入力します。

![cast 承認後のプロフィール編集](images/account_creation/cast_invitation/08_after_accept_profile_edit.png)

![cast プロフィール入力済み](images/account_creation/cast_invitation/09_profile_filled.png)

7. プロフィールを更新すると、ブース編集画面へ移動します。ブース名や説明文を確認・編集します。

![cast プロフィール更新後のブース編集](images/account_creation/cast_invitation/10_after_profile_booth_edit.png)

![cast ブース編集入力済み](images/account_creation/cast_invitation/11_booth_filled.png)

8. ブースを更新すると、トップ画面へ移動します。

![cast ブース更新後のトップ画面](images/account_creation/cast_invitation/12_after_booth_update_home.png)

TODO: cast（配信者）の初回設定で必須にする項目と、配信開始前に確認すべき項目を確定してください。

## 追加 store_admin（店舗管理者）招待 URL を発行する

追加の store_admin（店舗管理者）は、既存の store_admin（店舗管理者）から発行された invitation（招待）URL を使ってアカウントを作成します。

1. store_admin（店舗管理者）でログインし、store_admin invitation（店舗管理者招待）画面を開きます。

![store_admin 招待発行画面](images/account_creation/store_admin_invitation/01_admin_invitation_form.png)

2. 招待 URL を発行します。発行された URL を、追加したい store_admin（店舗管理者）へ共有します。

![store_admin 招待 URL 発行後](images/account_creation/store_admin_invitation/02_admin_invitation_issued.png)

TODO: 誰が追加 store_admin（店舗管理者）を招待できるか、社内運用ルールに合わせて説明を追記してください。

## 追加 store_admin（店舗管理者）アカウントを作成する

1. 受け取った store_admin invitation（店舗管理者招待）URL を開きます。招待内容を確認します。

![store_admin 招待確認画面](images/account_creation/store_admin_invitation/03_invitation_guest.png)

2. 新規 store_admin アカウント作成へ進みます。

![store_admin アカウント作成フォーム](images/account_creation/store_admin_invitation/04_signup_form.png)

3. メールアドレス、パスワード、確認用パスワードを入力します。

![store_admin アカウント作成フォーム入力済み](images/account_creation/store_admin_invitation/05_signup_filled.png)

4. 登録ボタンを押します。登録後、招待確認画面へ戻ります。

![store_admin 登録後の招待確認](images/account_creation/store_admin_invitation/06_after_signup_invitation.png)

5. 招待を承認します。
6. 承認が完了すると、dashboard（ダッシュボード）へ移動します。

![store_admin 招待承認後のダッシュボード](images/account_creation/store_admin_invitation/07_after_accept_dashboard.png)

TODO: 招待 URL が使えない場合、すでに別 role（権限種別）でログインしている場合、期限切れの場合の説明を追加してください。

## system_admin（運営）アカウントについて

system_admin（運営）アカウントは、画面上の自己登録フローでは作成しません。

TODO: system_admin（運営）アカウントの作成・付与手順は、管理者向け運用手順として別章または非公開手順に分けるか判断してください。

# 共通操作

## ログイン / ログアウト

ログイン画面でメールアドレスとパスワードを入力してログインします。ログイン後は、画面上部のユーザーメニューからログアウトできます。

TODO: 電話番号ログイン、パスワード再設定、メール確認の有無は、実運用の案内文に合わせて追記してください。

## dashboard（ダッシュボード）を確認する

ログイン後の dashboard（ダッシュボード）には、自分の role（権限種別）で利用できる操作カードが表示されます。表示されるカードは role（権限種別）や、現在選択中の Store（店舗）/ booth（ブース）によって異なります。

## プロフィールを編集する

プロフィール編集では、表示名、自己紹介、プロフィール画像を編集できます。customer（視聴者）と cast（配信者）は、初回登録後にプロフィール編集へ進む場合があります。

## 電話番号を認証する

電話番号認証では、SMS（ショートメッセージ）で届いた OTP（ワンタイム認証コード）を使って電話番号を確認します。

TODO: OTP 入力画面、期限切れ、再送、試行回数超過の説明は別途追記します。

# customer（視聴者）向け操作

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

TODO: プロフィール画像アップロードの具体的な操作と推奨画像サイズは、別途追記します。

## 電話番号を認証する

1. dashboard（ダッシュボード）で「電話番号認証」を開きます。
2. 現在の認証状況を確認します。
3. 新しい電話番号を登録する場合は、電話番号を入力します。
4. 「認証コードを送信」を押します。
5. SMS（ショートメッセージ）で届いた認証コードを入力します。

![電話番号認証フォーム](images/customer/phone/01_new_form.png)

入力済みの例です。

![電話番号認証入力済み](images/customer/phone/02_new_filled.png)

TODO: SMS OTP（ショートメッセージのワンタイム認証コード）送信後の認証コード入力画面とエラー表示は、別途追記します。

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

TODO: コメント送信後にコメント欄へ反映される状態は、別途追記します。

## ドリンクを送る

1. live（配信中）視聴画面でドリンクアイコンを押します。
2. ドリンクメニューを確認します。
3. 送りたいドリンクを選択します。

![ドリンクメニュー](images/customer/live/03_drink_menu.png)

ドリンク送信にはポイント残高が必要です。送信したドリンクは cast（配信者）側で pending drink orders（未消化ドリンク）として表示され、cast（配信者）が消化すると売上に反映されます。

TODO: ドリンク送信後のポイント残高、未消化ドリンク表示、cast（配信者）側の消化操作は別途追記します。

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

# cast（配信者）向け操作

## dashboard（ダッシュボード）を確認する

ログイン後、dashboard（ダッシュボード）には cast（配信者）が使う画面へのカードが表示されます。

![cast dashboard](images/cast/dashboard/01_dashboard.png)

主なカードは次のとおりです。

- 「プロフィール編集」: 表示名や自己紹介を編集します。
- 「電話番号認証」: 電話番号の登録状況を確認します。
- 「ブース一覧」: 操作対象の booth（ブース）を選択します。
- 「ブース情報」: 現在の booth（ブース）の情報を確認します。
- 「配信履歴」: 現在の booth（ブース）の過去配信を確認します。
- 「ブース編集」: 現在の booth（ブース）の名前や説明文を編集します。

TODO: ブースが1件だけの場合に「ブース一覧」カードが表示されるかは、運用データの状態に合わせて補足します。

## booth（ブース）一覧を確認する

1. dashboard（ダッシュボード）から「ブース一覧」を開きます。
2. 所属している booth（ブース）が一覧表示されます。
3. 操作対象として選択中の booth（ブース）には「選択中」と表示されます。

![ブース一覧](images/cast/booths/01_index.png)

ブース一覧では、booth（ブース）の店舗名、ブース名、状態を確認できます。

![選択中ブース](images/cast/booths/03_index_current_booth.png)

「配信」を押すと配信画面の入口へ進みます。実際の配信開始は、配信画面で状態を確認してから行います。

TODO: 複数 booth（ブース）間の切り替え時に配信中または席外し中の booth（ブース）がある場合の注意文を追加します。

## booth（ブース）情報を確認する

1. dashboard（ダッシュボード）から「ブース情報」を開きます。
2. booth（ブース）の名前、所属店舗、担当 cast（配信者）を確認します。
3. 必要に応じて、共有、編集、配信履歴へ進みます。

![ブース情報](images/cast/booths/02_show.png)

「ブースを共有」から booth（ブース）の URL を共有できます。

TODO: 共有ボタンの挙動はブラウザや端末によって異なるため、対応ブラウザ別の説明を追記します。

## booth（ブース）を編集する

1. dashboard（ダッシュボード）から「ブース編集」を開きます。
2. 「ブース名」と「説明文」を確認します。
3. 必要な項目を入力します。
4. 「更新する」を押します。

![ブース編集フォーム](images/cast/booth_edit/01_edit_form.png)

入力済みの例です。

![ブース編集入力済み](images/cast/booth_edit/02_edit_filled.png)

更新が完了すると dashboard（ダッシュボード）へ戻り、「ブースを更新しました」と表示されます。

![ブース更新後](images/cast/booth_edit/03_after_update_dashboard.png)

サムネ画像を設定できる場合があります。画像を変更する場合は、画面上のアップロード欄から画像を選択してください。

TODO: サムネ画像アップロードの具体的な操作と推奨画像サイズは、別途追記します。

## 配信画面の入口を開く

1. booth（ブース）一覧で「配信」を押します。
2. 配信画面が開きます。
3. 配信前の状態では、配信タイトル入力欄と「配信開始」ボタンが表示されます。

![配信画面入口](images/cast/live/01_live_standby_initial.png)

この画面では、配信タイトルを設定できます。未入力の場合は booth（ブース）名が表示されます。

TODO: 「配信開始」を押したあとの実配信開始、カメラ / マイク許可、席外し、復帰、配信終了は別途追記予定です。

## 配信履歴を確認する

1. dashboard（ダッシュボード）から「配信履歴」を開きます。
2. 現在の booth（ブース）の終了済み配信が一覧表示されます。
3. 履歴がない場合は、空状態のメッセージが表示されます。

![配信履歴 空状態](images/cast/stream_sessions/01_index_empty.png)

TODO: 終了済み配信がある場合の一覧表示と配信リザルト画面は別途追記します。

## pending drink orders（未消化ドリンク）を確認する

配信画面では、customer（視聴者）から送られた drink order（ドリンク注文）を確認し、必要に応じて消化します。

未消化ドリンクがない場合は、空状態のメッセージが表示されます。

![未消化ドリンクなし](images/cast/drink_orders/01_pending_empty.png)

TODO: customer（視聴者）によるドリンク送信、cast（配信者）による消化、返却処理は別途追記します。

## 配信開始・席外し・復帰・終了

TODO: 以下の操作は、外部配信サービス、カメラ、マイク、画面加工機能への依存を確認したうえで、別途追記します。

- 配信を開始する。
- カメラ / マイクを許可する。
- 席外しにする。
- 配信に復帰する。
- 配信を終了する。
- 配信リザルトを確認する。

# store_admin（店舗管理者）向け操作

## dashboard（ダッシュボード）を確認する

ログイン後、dashboard（ダッシュボード）では店舗管理に必要な画面へのカードが表示されます。

![store_admin dashboard](images/store_admin/dashboard/01_dashboard.png)

主なカードは、店舗を選択、ブース管理、店舗設定編集、キャスト一覧、キャスト招待、店舗管理者招待、配信者別数値一覧、ドリンクメニュー、通報一覧、振込先口座設定、精算（予定・履歴）です。

TODO: 店舗が1件だけの場合に「店舗を選択」カードを表示するかどうかは、実運用の見せ方に合わせて説明を調整してください。

## 操作対象の店舗を選択する

複数店舗を管理している場合は、操作対象の店舗を選択します。

![店舗選択](images/store_admin/stores/01_index.png)

1. dashboard（ダッシュボード）から「店舗を選択」を開きます。
2. 操作したい店舗の「この店舗に切替」を押します。
3. 選択中の店舗が切り替わります。

## 店舗情報を編集する

店舗名、概要、地域、業態、電話番号、営業時間、各種 URL などを編集できます。

![店舗設定編集フォーム](images/store_admin/stores/02_edit_form.png)

1. dashboard（ダッシュボード）から「店舗設定編集」を開きます。
2. 必要な項目を入力します。

![店舗設定編集フォーム入力済み](images/store_admin/stores/03_edit_filled.png)

3. 「更新する」を押します。
4. 更新が完了すると dashboard（ダッシュボード）へ戻ります。

![店舗情報更新後](images/store_admin/stores/04_after_update_dashboard.png)

TODO: 住所を保存すると座標取得が走る実装です。公開マニュアルでは、住所入力の扱いと外部地図連携の有無を確認してから説明してください。

## ブースを管理する

ブース管理画面では、ブースの一覧確認、新規作成、操作対象ブースの切替、ブース編集への移動ができます。

![ブース管理一覧](images/store_admin/booths/01_index.png)

### ブースを作成する

1. ブース管理画面で「新規作成」を押します。

![ブース作成フォーム](images/store_admin/booths/02_new_form.png)

2. ブース名、説明文を入力します。必要に応じて所属キャストを選択します。

![ブース作成フォーム入力済み](images/store_admin/booths/03_new_filled.png)

3. 「作成する」を押します。
4. 作成が完了すると dashboard（ダッシュボード）へ移動します。

![ブース作成後](images/store_admin/booths/04_after_create_dashboard.png)

5. ブース管理画面へ戻ると、作成したブースが一覧に表示されます。

![ブース作成後の一覧反映](images/store_admin/booths/05_index_after_create.png)

注意:

- 閉鎖、強制終了などの操作は影響が大きいため、実行前に対象ブースと状態を確認してください。
- Phase1 ではブース紐づけは確定後変更不可の前提があります。

TODO: 公開マニュアルでは、紐づけ変更できない点をより目立つ注意として整理してください。

## キャスト一覧を確認する

キャスト一覧では、店舗に所属している cast（配信者）と所属ブースを確認できます。

![キャスト一覧](images/store_admin/casts/01_index.png)

注意:

- 「削除」は cast（配信者）の所属解除です。関連ブースがアーカイブされる場合があります。
- この操作は取り消しや影響範囲を確認してから実行してください。

## キャストを招待する

cast invitation（配信者招待）画面では、cast（配信者）を店舗へ招待する URL を発行できます。

![キャスト招待画面](images/store_admin/invitations/01_cast_invitation_index.png)

1. 必要に応じてメモを入力します。

![キャスト招待メモ入力済み](images/store_admin/invitations/02_cast_invitation_filled.png)

2. 招待 URL を発行します。
3. 発行された URL を招待対象の cast（配信者）へ共有します。

![キャスト招待 URL 発行後](images/store_admin/invitations/03_cast_invitation_issued.png)

TODO: 招待 URL の有効期限、再発行、共有方法、送付文面を運用ルールに合わせて追記してください。

## 店舗管理者を招待する

store_admin invitation（店舗管理者招待）画面では、追加の store_admin（店舗管理者）を店舗へ招待する URL を発行できます。

![店舗管理者招待画面](images/store_admin/invitations/04_store_admin_invitation_index.png)

1. 「招待 URL を発行」を押します。
2. 発行された URL を追加したい店舗管理者へ共有します。

![店舗管理者招待 URL 発行後](images/store_admin/invitations/05_store_admin_invitation_issued.png)

TODO: 店舗管理者を追加できる条件と、退職・担当変更時の運用を追記してください。

## ドリンクメニューを管理する

ドリンクメニュー画面では、視聴者が送れるドリンクの名前、価格、表示順、有効 / 無効を管理できます。

![ドリンクメニュー一覧](images/store_admin/drink_items/01_index.png)

### ドリンクを追加する

1. 新規作成フォームにドリンク名、価格、表示順を入力します。

![ドリンク新規作成入力済み](images/store_admin/drink_items/02_new_filled.png)

2. 「新規作成」を押します。
3. 保存後、一覧に新しいドリンクが表示されます。

![ドリンク作成後の一覧反映](images/store_admin/drink_items/03_after_create.png)

注意:

- 価格はポイント単位です。
- 無効にしたドリンクは通常の注文対象から外れます。

TODO: ドリンク編集と無効化の詳細な運用ルールを追記してください。

## 配信者別数値一覧を確認する

配信者別数値一覧では、cast（配信者）ごとの配信売上、配信時間、売上 / 時間などを確認できます。

![配信者別数値一覧](images/store_admin/metrics/01_index.png)

配信実績がない cast（配信者）も含める場合は、「配信実績がない配信者も表示する」を使います。

![配信者別数値一覧 全キャスト表示](images/store_admin/metrics/02_all_casts.png)

TODO: 売上計算の対象は「消化確定済みドリンクのみ」という Phase1 前提を、精算章と合わせて説明してください。

## 通報一覧を確認する

通報一覧では、店舗の配信コメントに対する通報を確認できます。

![通報一覧](images/store_admin/comment_reports/01_index.png)

注意:

- BAN、BAN解除、却下は影響の大きい操作です。

TODO: 通報対応の判断基準、対応後のユーザーへの影響、運営へのエスカレーション条件を追記してください。

## 振込先口座を設定する

振込先口座設定では、精算時の入金先を登録します。

![振込先口座設定フォーム](images/store_admin/payout_account/01_edit_form.png)

1. 口座の種類を選択します。
2. 銀行コード、支店コード、預金種目、口座番号、口座名義カナを入力します。

![振込先口座設定入力済み](images/store_admin/payout_account/02_edit_filled.png)

3. 「更新する」を押します。
4. 更新後、登録済み口座は一部だけマスクされて表示されます。

![振込先口座設定更新後](images/store_admin/payout_account/03_after_update.png)

注意:

- 実際の銀行口座情報は、必ず店舗が管理する正しい情報を入力してください。
- 画面上では既存口座番号の全桁は表示されません。

TODO: 口座情報の確認フローと、変更できる担当者のルールを追記してください。

## 精算（予定・履歴）を確認する

精算画面では、次回精算予定の概算と、確定済み精算履歴を確認できます。

![精算予定・履歴](images/store_admin/settlements/01_index.png)

表示される情報:

- 集計期間
- 支払予定額
- 当月の消化 pt 合計
- 店舗取り分
- 前月からの繰越
- 精算履歴

注意:

- 表示金額は概算です。
- 精算は月次で行われます。
- 1万円未満は翌月へ繰り越されます。

TODO: 確定済み精算の詳細画面と、振込予定日の説明を追記してください。

# system_admin（運営）向け操作

## ダッシュボードを確認する

system_admin（運営）でログインし、ダッシュボードを開きます。

![system_admin ダッシュボード](images/system_admin/dashboard/01_dashboard.png)

ダッシュボードには、ユーザー管理、紹介コード管理、お知らせ管理、Effect 管理、店舗BAN、精算一覧、振込CSV、マニュアル精算などの入口が表示されます。

TODO: 実運用で system_admin（運営）アカウントを誰が発行し、どの手順で初期パスワードを渡すかは別途追記します。

## 店舗を選択する

店舗BANなど、admin namespace（店舗管理側画面）の一部機能では操作対象店舗の選択が必要です。ダッシュボードの「店舗を選択」または対象機能の導線から店舗選択画面を開きます。

![店舗選択](images/system_admin/admin_stores/01_store_select.png)

対象店舗の「この店舗に切替」を選ぶと、選択中の店舗が切り替わり、ダッシュボードへ戻ります。

![店舗選択後](images/system_admin/admin_stores/02_after_store_select_dashboard.png)

## ユーザーを管理する

「ユーザー管理」を開くと、ユーザーの一覧を確認できます。

![ユーザー一覧](images/system_admin/users/01_index.png)

「新規作成」を選ぶと、ユーザー作成フォームが表示されます。

![ユーザー作成フォーム](images/system_admin/users/02_new_form.png)

email（メールアドレス）、role（権限種別）、password（パスワード）、password_confirmation（パスワード確認）を入力します。

![ユーザー作成入力済み](images/system_admin/users/03_filled.png)

「作成する」を選ぶとユーザー一覧へ戻り、作成したユーザーが表示されます。

![ユーザー作成後](images/system_admin/users/04_after_save.png)

注意: 実コード上、store_admin（店舗管理者）はこの画面から作成・変更できません。store_admin（店舗管理者）は店舗登録または店舗管理者 invitation（招待）経由で作成します。

TODO: ユーザー停止、role（権限種別）変更、復元に関する運用基準を追記します。今回のマニュアルでは停止や降格の具体操作は未確定です。

## 紹介コードを管理する

「紹介コード管理」を開くと、ReferralCode（紹介コード）の一覧を確認できます。

![紹介コード一覧](images/system_admin/referral_codes/01_index.png)

「新規作成」を選ぶと、紹介コード作成フォームが表示されます。

![紹介コード作成フォーム](images/system_admin/referral_codes/02_new_form.png)

code（コード）、label（識別用ラベル）、expires_at（有効期限）、enabled（有効）を入力します。

![紹介コード作成入力済み](images/system_admin/referral_codes/03_filled.png)

「作成する」を選ぶと紹介コード一覧へ戻り、作成したコードが表示されます。

![紹介コード作成後](images/system_admin/referral_codes/04_after_save.png)

TODO: 紹介コードの配布方法、期限切れ時の案内、無効化の運用基準を追記します。

## お知らせを管理する

「お知らせ管理」を開くと、お知らせの一覧を確認できます。

![お知らせ一覧](images/system_admin/notifications/01_index.png)

「新規作成」を選ぶと、お知らせ作成フォームが表示されます。

![お知らせ作成フォーム](images/system_admin/notifications/02_new_form.png)

タイトル、本文、公開日時、enabled（有効）、タグを入力します。新規タグはカンマまたは改行区切りで追加できます。

![お知らせ作成入力済み](images/system_admin/notifications/03_filled.png)

「作成する」を選ぶとお知らせ一覧へ戻り、作成したお知らせが表示されます。

![お知らせ作成後](images/system_admin/notifications/04_after_save.png)

TODO: 公開前確認、非公開化、重要告知のタグ運用、実ユーザーへの通知タイミングを追記します。

## Effect を管理する

「Effect管理」を開くと、Effect（配信画面のエフェクト）の一覧を確認できます。

![Effect一覧](images/system_admin/effects/01_index.png)

「新規作成」を選ぶと、Effect 作成フォームが表示されます。

![Effect作成フォーム](images/system_admin/effects/02_new_form.png)

表示名、key（一意キー）、zip_filename（配置済み zip ファイル名）、icon_path（アイコンパス）、position（表示順）、enabled（有効）を入力します。

![Effect作成入力済み](images/system_admin/effects/03_filled.png)

「作成する」を選ぶと Effect 一覧へ戻り、作成した Effect が表示されます。

![Effect作成後](images/system_admin/effects/04_after_save.png)

TODO: Banuba / DeepAR（画面加工）のファイル配置、ライセンス確認、配信画面での表示確認手順を追記します。

## 店舗BANを確認する

店舗を選択した状態で「店舗BAN」を開くと、対象店舗の BAN 管理画面が表示されます。

![店舗BAN一覧](images/system_admin/store_bans/01_index.png)

BAN対象と理由を入力できます。

![店舗BAN入力例](images/system_admin/store_bans/02_form_filled_not_submitted.png)

TODO: BAN作成、BAN解除、通報起点の対応手順、解除判断の基準を追記します。実行前に運用責任者の確認が必要です。

## 精算一覧を確認する

「精算一覧」を開くと、settlement（精算）データを確認できます。

![精算一覧](images/system_admin/settlements/01_index.png)

TODO: draft / confirmed / exported / paid の状態ごとの意味、確定、支払済み更新、取消に相当する運用を追記します。

## 振込 CSV を確認する

「振込CSV（住信SBI）」を開くと、settlement export（精算書き出し）の一覧を確認できます。

![振込CSV一覧](images/system_admin/settlement_exports/01_index.png)

詳細を開くと、format（形式）、record count（件数）、total amount（金額合計）、生成者、生成日時を確認できます。

![振込CSV詳細](images/system_admin/settlement_exports/02_show.png)

TODO: CSV生成、CSVダウンロード、銀行アップロード後の確認、支払済み更新の手順を追記します。

## マニュアル精算をプレビューする

「マニュアル精算（テスト）」を開くと、手動で精算対象期間を指定するフォームが表示されます。

![マニュアル精算フォーム](images/system_admin/manual_settlements/01_manual_form.png)

対象店舗、period_from（開始日時）、period_to（終了日時）を入力します。

![マニュアル精算入力済み](images/system_admin/manual_settlements/02_manual_filled.png)

「プレビュー」を選ぶと、gross_yen（総額）、store_share_yen（店舗取り分）、platform_fee_yen（手数料）が表示されます。マニュアル精算（テスト）では繰越額を適用しません。

![マニュアル精算プレビュー](images/system_admin/manual_settlements/03_manual_preview.png)

TODO: 「確定（confirmedで作成）」を押す前の承認フロー、作成後の修正可否、重複期間の扱いを追記します。

# 困ったとき

## 招待 URL が使えない

TODO: 招待 URL の期限切れ、使用済み、role（権限種別）違い、すでにログイン中の場合の画面と問い合わせ先を追記します。

## 電話番号認証コードが届かない

TODO: SMS OTP（ショートメッセージのワンタイム認証コード）が届かない場合の再送、入力期限、問い合わせ先を追記します。

## ポイント購入が完了しない

TODO: Stripe Checkout（Stripe の決済画面）で支払いが完了しない場合の確認事項を追記します。

## 配信画面でカメラ / マイクが使えない

TODO: ブラウザ権限、OS 権限、カメラ / マイク選択、Banuba / DeepAR（画面加工）の token / license が未設定の場合の案内を追記します。

## booth（ブース）や Store（店舗）を開けない

TODO: offline（オフライン）状態、店舗BAN、権限不足、操作対象の店舗 / booth（ブース）が未選択の場合の案内を追記します。

## 精算や振込 CSV の操作に迷った

TODO: 精算確定、CSV生成、CSVダウンロード、銀行アップロード、支払済み更新は影響が大きいため、運用責任者の確認手順を追記します。

# 未確認事項 / 今後追記予定

以下は、今後の撮影・仕様確認後に追記する予定です。

- comment（コメント）送信後の表示。
- drink order（ドリンク注文）送信後の表示。
- cast（配信者）によるドリンク消化。
- 配信開始 / 席外し / 復帰 / 配信終了。
- 終了済み stream session（配信セッション）の配信履歴とリザルト。
- Stripe Checkout（Stripe の決済画面）での購入完了。
- SMS OTP（ショートメッセージのワンタイム認証コード）入力。
- mobile（スマートフォン幅）での操作。
- 実 IVS join（Amazon IVS への参加）を伴う映像視聴。
- プロフィール画像、店舗画像、ブースサムネイルのアップロード。
- customer（視聴者）のお気に入り追加 / 解除。
- store_admin（店舗管理者）の通報対応、BAN、BAN解除、ブース閉鎖、配信強制終了。
- system_admin（運営）のユーザー停止、紹介コード無効化、お知らせ無効化、Effect 無効化、店舗BAN作成 / 解除、精算確定、支払済み更新、振込 CSV 生成 / ダウンロード、マニュアル精算確定。
