# system_admin（運営）向け操作マニュアルドラフト

この章は、system_admin（運営）としてログインした後の通常操作を説明するためのドラフトです。画面名や遷移は実コードと Playwright（ブラウザ自動操作）で取得したスクリーンショットを根拠にしています。危険操作は今回実行していないため、該当箇所には TODO を残しています。

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

TODO: ユーザー停止、role（権限種別）変更、復元に関する運用基準を追記します。今回の撮影では停止や降格は実行していません。

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

BAN対象と理由を入力できますが、今回の撮影では BAN 作成は実行していません。

![店舗BAN入力例](images/system_admin/store_bans/02_form_filled_not_submitted.png)

TODO: BAN作成、BAN解除、通報起点の対応手順、解除判断の基準を追記します。実行前に運用責任者の確認が必要です。

## 精算一覧を確認する

「精算一覧」を開くと、settlement（精算）データを確認できます。

![精算一覧](images/system_admin/settlements/01_index.png)

TODO: draft / confirmed / exported / paid の状態ごとの意味、確定、支払済み更新、取消に相当する運用を追記します。今回の撮影では確定・支払済み更新は実行していません。

## 振込 CSV を確認する

「振込CSV（住信SBI）」を開くと、settlement export（精算書き出し）の一覧を確認できます。

![振込CSV一覧](images/system_admin/settlement_exports/01_index.png)

詳細を開くと、format（形式）、record count（件数）、total amount（金額合計）、生成者、生成日時を確認できます。

![振込CSV詳細](images/system_admin/settlement_exports/02_show.png)

TODO: CSV生成、CSVダウンロード、銀行アップロード後の確認、支払済み更新の手順を追記します。今回の撮影では CSV ダウンロードと生成は実行していません。

## マニュアル精算をプレビューする

「マニュアル精算（テスト）」を開くと、手動で精算対象期間を指定するフォームが表示されます。

![マニュアル精算フォーム](images/system_admin/manual_settlements/01_manual_form.png)

対象店舗、period_from（開始日時）、period_to（終了日時）を入力します。

![マニュアル精算入力済み](images/system_admin/manual_settlements/02_manual_filled.png)

「プレビュー」を選ぶと、gross_yen（総額）、store_share_yen（店舗取り分）、platform_fee_yen（手数料）、carryover_yen（繰越額）が表示されます。

![マニュアル精算プレビュー](images/system_admin/manual_settlements/03_manual_preview.png)

TODO: 「確定（confirmedで作成）」を押す前の承認フロー、作成後の修正可否、重複期間の扱いを追記します。今回の撮影では確定作成は実行していません。
