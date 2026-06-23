# store_admin（店舗管理者）向け操作マニュアル ドラフト

この章では、store_admin（店舗管理者）が店舗・ブース・キャスト・ドリンクメニュー・精算関連情報を確認、管理する手順を説明します。

TODO: 公開マニュアルでは、各店舗の運用ルールに合わせて「誰がどの操作を行うか」を追記してください。

## dashboard（ダッシュボード）を確認する

ログイン後、dashboard（ダッシュボード）では店舗管理に必要な画面へのカードが表示されます。

![store_admin dashboard](images/store_admin/dashboard/01_dashboard.png)

主なカード:

- 店舗を選択
- ブース管理
- 店舗設定編集
- キャスト一覧
- キャスト招待
- 店舗管理者招待
- 配信者別数値一覧
- ドリンクメニュー
- 通報一覧
- 振込先口座設定
- 精算（予定・履歴）

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
- Phase1 ではブース紐づけは確定後変更不可の前提があります。TODO: 公開マニュアルでは、紐づけ変更できない点をより目立つ注意として整理してください。

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
- TODO: ドリンク編集と無効化の詳細な運用ルールを追記してください。

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
- TODO: 通報対応の判断基準、対応後のユーザーへの影響、運営へのエスカレーション条件を追記してください。

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
- TODO: 口座情報の確認フローと、変更できる担当者のルールを追記してください。

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
- TODO: 確定済み精算の詳細画面と、振込予定日の説明を追記してください。
