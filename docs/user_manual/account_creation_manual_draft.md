# アカウント作成

この章では、Butterflyve を利用するためのアカウント作成方法を説明します。利用できる作成方法は role（権限種別）によって異なります。

TODO: 公開マニュアルでは、招待 URL や紹介コードを受け取る具体的な案内文を運用ルールに合わせて追記してください。

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

store_admin（店舗管理者）は、紹介コードつきの店舗登録 URL から店舗とアカウントを同時に作成します。

1. 受け取った店舗登録 URL を開きます。URL には referral code（紹介コード）が含まれる場合があります。

   ![店舗登録フォーム](images/account_creation/store_admin_registration/01_registration_form.png)

2. 店舗名、メールアドレス、パスワード、確認用パスワード、紹介コードを入力します。

   ![店舗登録フォーム入力済み](images/account_creation/store_admin_registration/02_registration_filled.png)

3. 登録ボタンを押します。

4. 登録が完了すると、店舗設定編集画面へ移動します。店舗情報を確認し、必要に応じて編集します。

   ![店舗登録後の店舗設定編集](images/account_creation/store_admin_registration/03_after_registration_store_edit.png)

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

system_admin（運営）アカウントは、今回確認した画面上の自己登録フローでは作成しません。

TODO: system_admin（運営）アカウントの作成・付与手順は、管理者向け運用手順として別章または非公開手順に分けるか判断してください。
