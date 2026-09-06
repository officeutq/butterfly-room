# 1. Phase1 アプリケーション設計（Rails）

## 1.0. 設計方針

* **Controllerは“認可→Service呼び出し→レスポンス”のみ**
* **状態変更・金銭処理はServiceに集約**
* **DBトランザクションはServiceの中で持つ**
* **通知（Turbo Streams）は“結果に応じて”Notifierに集約**
* **PresenceはServiceで抽象化**（DB→Redis差し替え可能に）

* **認証は Devise（User）を採用**：`users` は email+password を基本とし、`role`（enum）で customer/cast/store_admin/system_admin を管理

---

## 1.0.1 認証/認可（Devise）

### 認証

* Devise によるセッション認証を使用する
  * 基本は `before_action :authenticate_user!`
* ログイン主体は `User`（単一テーブル）

### ロール（権限）

* `users.role` を enum で管理（DB設計に準拠）
* ルーティング/Controller では「認証 → ロール/所属チェック → Service」の順に統一する
  * ロール/所属チェックは Policy（Pundit など）または `before_action` で実装（方針は後続Issueで確定）
* Deviseの認証・パスワード再設定検索は`users.deleted_at IS NULL`に限定する
* email / phone_numberの一意性は、model validationとDBの部分一意indexの両方で有効ユーザー間に限定する

### ユーザー自身の退会

* routeは`GET /account_withdrawal`（確認モーダル）と`DELETE /account_withdrawal`（実行）を使用する
* `AccountWithdrawalsController`は、認証、system_admin除外、現在のパスワード、確認チェック、Service呼び出し、ログアウト、レスポンスだけを担当する
* `Accounts::WithdrawalService`は、対象ユーザーと管理店舗をlockし、ロール別クリーンアップ完了後に`users.deleted_at`を設定する
* `StoreMemberships::RemoveCastService`は、配信終了、ドリンク返却、関連ブースのアーカイブ、キャスト所属解除を共通化し、店舗管理画面と退会処理から利用する
* `Booths::CloseAndArchiveService`は、必要な配信終了後にブース状態を再確認してアーカイブする
* store_admin退会時は、退会者以外の`users.deleted_at IS NULL`な管理者所属を有効管理者として数える
* 他に有効な管理者がいる店舗は変更せず、唯一管理者店舗だけを非公開化してブース・キャスト所属・未使用招待を整理する
* IVS等の外部処理を含むため、各クリーンアップは完了済み状態を許容し、失敗後に再実行できる冪等性を持たせる


---

## 1.1. ディレクトリ/クラス構成

09_最新ディレクトリ構成.md を参照

> Serviceが増えるのはOK。MVPでも「金銭と状態」があるので、
> Controller肥大化を避けるために最初から分けるのが得策。

---

## 1.2. Controller設計（薄くする）

### 1.2.1 顧客：ドリンク送信

`StreamSessions::DrinkOrdersController#create`

責務

1. Devise認証（authenticate_user!）＋role=customer を確認
2. BANチェック（Policy or before_action）
3. Service呼び出し
4. 成功→JSON返す、失敗→エラーコード返す

---

### 1.2.2 キャスト：消化

`Cast::DrinkOrdersController#consume`

責務

* Service呼び出しだけ
  （FIFOはService側で完全に担保）

---

### 1.2.3 キャスト：配信開始/終了

`Cast::StreamSessionsController#create / #end`

責務

* Policyで「そのブースに所属しているか」
* Serviceで開始/終了

---

## 1.3. Service責務（最重要）

### 1.3.1 StreamSessions::StartService

**入力**

* booth_id
* actor_cast_user_id

**処理（トランザクション）**

* boothの現在状態を確認（offlineのみ開始可）
* stream_session作成（started_at）
* booth.status=live + booth.current_stream_session_id セット
* Notifierで status更新配信（必要なら）

**出力**

* stream_session

**例外**

* already_live（409）

---

### 1.3.2 StreamSessions::StatusService（席外し）

**入力**

* booth_id
* actor_cast_user_id
* status（away/live）

**処理**

* booth.current_stream_session_id があること
* booth.status が遷移可能であること
* booth.status 更新
* Notifierで視聴側の状態UI更新（eventsでreplace）

---

### 1.3.3 StreamSessions::EndService（配信終了）

**入力**

* stream_session_id
* actor_user_id（cast/admin）

**処理（トランザクション）**

1. stream_sessionをロックして終了済みでないこと確認
2. boothをoffline化（current_stream_session_id=null）
3. `DrinkOrders::RefundService` を呼ぶ（pending→refunded一括）
4. stream_session.ended_at 更新
5. Notifierで終了通知（顧客/キャスト）

**出力**

* refunded_count, refunded_points_sum

**例外**

* already_ended（409）

---

### 1.3.4 DrinkOrders::CreateService（pending作成）

**入力**

* stream_session_id
* customer_user_id
* drink_item_id

**処理（トランザクション）**

1. セッション/ブース状態チェック（live/awayのみ）

3. itemが store に属し enabled であること確認
4. `Wallets::HoldService`（available↓ reserved↑）
5. drink_order(pending)作成
6. wallet_transaction(hold)作成（採用する場合）
7. Notifierで未消化キュー更新（キャスト向けreplace）

**出力**

* drink_order, wallet

**例外**

* insufficient_points（402）
* session_ended / booth_offline（409）

---

### 1.3.5 DrinkOrders::ConsumeService（FIFO消化）

**入力**

* drink_order_id
* actor_cast_user_id

**処理（トランザクション）**

1. drink_orderをロック
2. status=pendingか確認
3. `DrinkOrders::FifoGuard` で「先頭pending」か確認

   * クエリで先頭pending（created_at asc, id asc）を取り、id一致を検証
4. drink_orderをconsumedに更新（consumed_at）
5. `Wallets::ConsumeService`（reserved減算）
   ※Holdした分を確定へ回す
6. store_ledger_entries作成（unique(drink_order_id)で二重計上防止）
7. wallet_transaction(consume)記録（任意）
8. Notifierで未消化キュー更新（replace）＋売上表示更新（任意）

**出力**

* consumed_order, new_wallet, store_points_delta

**例外**

* not_head（409）
* already_consumed/refunded（409）
* session_ended（409）

---

### 1.3.6 DrinkOrders::RefundService（返却）

**入力**

* stream_session_id

**処理（トランザクション内で呼ばれる想定）**

1. pending注文を `FOR UPDATE` でロックしつつ取得
2. 合計pointsを算出（storeごと/顧客ごとが必要なら分ける）
3. pending→refundedに更新（refunded_at）
4. 顧客Walletをまとめて release（reserved→available）

   * 注文が複数顧客に跨るので、顧客ごとに集計して更新（MVPでもここは必要）
5. wallet_transaction(release) を顧客ごとに記録（任意）
6. Notifierで返却/終了通知（顧客向けはセッション終了通知にまとめてもOK）

**出力**

* refunded_count, refunded_points_sum

> ※返却は「顧客ごとに集計してWallet更新」が必須です
> （1セッションに複数顧客がいるため）

---

### 1.3.7 Presences::PingService / SummaryService

**Ping**

* joined_at作成 or last_seen更新
* endedなら409

**Summary**

* viewer_count算出（DBでCOUNT、将来Redisへ差し替え）

---

## 1.4. Notifier設計（Turbo Streams配信を集約）

### 1.4.1 CommentNotifier

* comment created → `comments`ストリームへappend

### 1.4.2 DrinkOrderNotifier

* pending作成/消化/返却で

  * キャスト画面の「未消化カラム」をreplace
  * （任意）顧客側へイベントappend

### 1.4.3 StreamSessionNotifier

* status変更（live/away/offline）で視聴画面の状態領域replace
* 終了で終了カードreplace

> Serviceが“状態を確定”し、Notifierが“表示を更新”する。
> これでロジックが散らばりません。

---

## 1.5. Queryオブジェクト（集計・表示用）

### 1.5.1 PendingDrinkOrdersQuery

* stream_session_id の pending を created_at順で返す
* キャスト画面の右カラム描画に使用

### 1.5.2 CastMetricsQuery（店舗管理）

* store_ledger_entries と stream_sessions を集計してキャスト別に返す

### 1.5.3 PresenceCountQuery

* last_seen threshold を引数に viewer_count を返す

---

## 1.6. 主要ユースケース疑似コード（設計確認用）

### 1.6.1 consume（FIFO）

* トランザクション開始
* order = DrinkOrder.lock.find(id)
* raise unless order.pending?
* head = DrinkOrder.pending.where(stream_session_id: order.stream_session_id).order(:created_at, :id).first
* raise not_head unless head.id == order.id
* order.consume!
* wallet = Wallet.lock.find_by(customer_user_id: order.customer_user_id)
* wallet.reserved -= order.price
* store_ledger_entries.create!(drink_order_id: order.id, points: order.price, ...)
* commit
* Notifier.replace_pending_list(order.stream_session_id)

---

### 1.6.2 end_stream（返却）

* トランザクション開始
* session = StreamSession.lock.find(id)
* raise if ended
* booth = Booth.lock.find(session.booth_id)
* booth.update!(status: :offline, current_stream_session_id: nil)
* refunds = group pending orders by customer_user_id
* for each customer:

  * wallet.lock.update!(reserved -= sum, available += sum)
  * update orders refunded
* session.update!(ended_at: now)
* commit
* Notifier.broadcast_end(session.id)

---

## 1.7. Phase1 実装に向けた“最低限の技術選択”

* コメント/通知：Turbo Streams + ActionCable
* キュー：Phase1は不要でもOK（Webhook処理だけはジョブ化推奨）
* Presence：DB（presences）で開始
* 監査：wallet_transactions / store_ledger_entries は入れる

---

了解。では続けて **Railsルーティング（REST構造）** と **モデル関連（ActiveRecord）**、さらに **enum/validation** と **マイグレーション順**まで、Phase1実装に直結する形でまとめます。
※プロジェクト前提（Rails + Hotwire/Turbo、form_with）に寄せます。

---

# 2. Rails ルーティング案（Phase1）

## 2.1 顧客導線（視聴・コメント・ドリンク・同接）

```ruby
Rails.application.routes.draw do
  # Customer
  root "home#show"
  get  "/welcome", to: "home#welcome"
  get  "/guest/auth_prompt", to: "guest_auth_prompts#show"
  get  "/home_feed", to: "home#feed" # JSONでもHTMLでもOK

  resources :stores, only: %i[show]

  resources :booths, only: %i[show] do
    # booth視聴画面。showで必要な初期データを提供
  end

  resources :stream_sessions, only: [] do
    # 同接
    get  :presence_summary, on: :member

    # presence ping
    resource :presence, only: [], module: :stream_sessions do
      post :ping
    end

    # コメント
    resources :comments, only: %i[create], module: :stream_sessions

    # ドリンク注文（pending作成）
    resources :drink_orders, only: %i[create], module: :stream_sessions

    resources :ivs_participant_tokens, only: %i[create], module: :stream_sessions

    get :presence_summary, on: :member
  end
end
```

### 公開閲覧と認証境界（Phase2）

* `home#show`、`home#welcome`、`stores#show`、`booths#show`、`booths#share`、`users#show`、`guest_auth_prompts#show` は `authenticate_user!` の対象外とする
* `stores#show` は `Store.published.find` で公開状態を必ず検証し、配下のブースは `active` のみ取得する
* `booths#show` は `Booth.active.in_published_stores.find`、未ログインの `users#show` はホームの配信者タブと共通の `User.public_profiles` に限定する。`booths#enter` は引き続き未ログインを `/welcome` へリダイレクトする
* `booths#share` も `Booth.active.in_published_stores.find` を再利用し、streamは対象ブースの関連から解決する。不正値・不存在・別ブースのstreamはブース共有へフォールバックし、ended済みでも対象ブースに属するstreamは配信共有に使用する
* 共有ページは公開情報だけの専用layoutを使用し、動的OGPと通常ブースへのJavaScript遷移を提供する。表示名は論理削除されておらず空欄でない `display_name` だけを利用し、メールアドレス等で代用しない。詳細は `docs/design/booth_sharing.md` を正とする
* お気に入りの作成・解除Controllerは従来どおり認証必須とし、未ログイン表示ではPOST/DELETE formを生成しない
* コメント・通報・ドリンク・お気に入り等の未ログイン保護操作は `guest_auth_prompt_path` を `modal` Turbo Frameへ読み込み、状態変更APIを呼ばず共通モーダルから `/welcome` へ進ませる
* `default_main` とbooth専用の `viewer_main` は、未ログイン時のフッター保護項目を認証必須pathへ直リンクせず、いずれも `guest_auth_prompt_path` へ統一する。公開プロフィールでも未ログイン用フッターを表示する
* `guest_auth_prompts#show` の通常GETは `/welcome` へリダイレクトし、Turbo Frameリクエストだけモーダル本文を返す
* ホーム、公開Store、公開booth、公開プロフィールを未ログインで表示する前に、残留しているDeviseの `unauthenticated` alertだけを削除し、アクセス可能な画面で誤ったログイン要求flashを表示しない
* IVS参加者トークンは未ログインのviewer要求だけを認証対象外とし、`Store.published`かつ`Booth.active`のcurrent stream_sessionへ`SUBSCRIBE` capabilityだけを発行する。publisher要求、コメント・ドリンク・presence endpointは引き続き認証必須とする
* 未ログインとログイン済みでboothの配信状態・コメントのTurbo Streamを分け、未ログイン用パーシャルにはpresence poll、視聴者数、状態変更formを含めない。各broadcastはログイン状態の区分だけで描画し、`current_user`等のリクエスト利用者固有情報を参照しない
* 未ログインでは在室ping・視聴者数summaryを呼び出さず、Presenceレコードを作成しない。BAN対象customerの既存guardは変更しない
* `home#show` のtitle、description、canonical、OGP、非表示H1はサービス公開トップとして設定し、ドメインルートを示す `WebSite` 構造化データを出力する。既存の表示要素と配置は変更しない
* `home#welcome` のtitle、description、canonical、OGPはログイン・視聴者アカウント新規作成の案内ページとして設定し、`WebSite` 構造化データは出力しない
* `stores#show` のdescriptionとOGP descriptionは `Stores::MetaDescriptionBuilder` で同一内容を生成する。登録済みの店舗名・エリア・業態の日本語表示名・営業時間・店舗説明だけを使用し、店舗説明の空白を正規化して最終結果を160文字以内とする。業態の「その他」は未入力として扱い、住所全文は使用しない
* `users#show` のカード・ヒーロー領域・OGPは1200x630pxの表示用`cover_image`を利用し、小型アイコン用の`avatar`や再編集用の`cover_image_source`を利用しない。カバー未設定時は共通ロゴへフォールバックする。公開プロフィールにはcanonicalと`profile` OGPを設定し、ログイン中の本人等だけが閲覧できる非公開プロフィールには`noindex,nofollow`を設定する
* Store / Boothの公開・管理カード、選択画面、ヒーロー、待機画面は40:21の表示用`thumbnail` / `thumbnail_image`を利用し、編集元添付を参照しない。一覧取得時は表示用attachmentとBlobを事前読込する
* Store OGPと新方式のBooth共有OGPは1200x630pxの表示用添付を再変換せず利用する。未移行の旧Booth画像だけは1200x630pxの互換variantを要求時に生成し、画像未設定時は1200x630pxの共通JPEGへフォールバックする
* sitemapは `/`、`/welcome`、`Store.published` の店舗詳細URLを列挙する。`noindex` の共有専用URLは追加しない

---

## 2.2 Wallet（ポイント購入）

```ruby
Rails.application.routes.draw do
  namespace :wallet do
    resources :purchases, only: %i[create] # checkout session作成
  end

  # Stripe return
  get "/checkout/return", to: "checkout#return"
  # Stripe webhook
  post "/webhooks/stripe", to: "webhooks/stripe#create"
end
```

---

## 2.3 キャスト導線（配信開始/終了/消化）

```ruby
Rails.application.routes.draw do
  namespace :cast do
    resources :booths, only: %i[index show edit update] do
      get :live, on: :member
      patch :status, on: :member
      resources :stream_sessions, only: %i[create], module: :booths
    end

    resources :stream_sessions, only: [] do
      post :finish, on: :member
      get  :pending_drink_orders, on: :member
    end

    resources :drink_orders, only: [] do
      post :consume, on: :member
    end
  end
end
```

---

## 2.4 店舗管理者（設定・集計・BAN）

```ruby
Rails.application.routes.draw do
  namespace :admin do
    root "dashboard#show"

    resource :store, only: %i[show update]
    resources :booths, only: %i[index show new edit create update] do
      member do
        get :watch
        patch :archive
      end
    end
    resources :drink_items, only: %i[index create update destroy]
    resources :store_bans, only: %i[index create destroy]
    resources :casts, only: %i[index create destroy]
    get "/cast_metrics", to: "metrics#cast"
  end
end
```

> destroyは論理削除推奨。MVPでは `enabled=false` で代替もOK。

---

# 3. ActiveRecord モデル関連（Phase1）

## 3.1 Store / Membership

* Store

  * has_many :store_memberships
  * has_many :members, through: :store_memberships, source: :user
  * has_many :booths
  * has_many :drink_items
  * has_many :store_bans

* StoreMembership

  * belongs_to :store
  * belongs_to :user

---

## 3.2 Booth / Cast

* Booth

  * belongs_to :store
  * belongs_to :current_stream_session, class_name: "StreamSession", optional: true
  * has_many :booth_casts
  * has_many :casts, through: :booth_casts, source: :cast_user
  * has_many :stream_sessions

* BoothCast

  * belongs_to :booth
  * belongs_to :cast_user, class_name: "User"

---

## 3.3 StreamSession / Presence / Comments

* StreamSession

  * belongs_to :store
  * belongs_to :booth
  * belongs_to :started_by_cast_user, class_name: "User"
  * has_many :presences
  * has_many :comments
  * has_many :drink_orders

* Presence

  * belongs_to :stream_session
  * belongs_to :customer_user, class_name: "User"

* Comment

  * belongs_to :stream_session
  * belongs_to :booth
  * belongs_to :user # customer
  * scope :alive, -> { where(deleted_at: nil) }

---

## 3.4 Wallet / Transactions

* Wallet

  * belongs_to :customer_user, class_name: "User"
  * has_many :wallet_transactions

* WalletTransaction

  * belongs_to :wallet
  * belongs_to :ref, polymorphic: true, optional: true

---

## 3.5 DrinkItem / DrinkOrder / StoreLedgerEntry

* DrinkItem

  * belongs_to :store

* DrinkOrder

  * belongs_to :store
  * belongs_to :booth
  * belongs_to :stream_session
  * belongs_to :customer_user, class_name: "User"
  * belongs_to :drink_item

* StoreLedgerEntry

  * belongs_to :store
  * belongs_to :stream_session
  * belongs_to :drink_order

---

## 3.6 StoreBan

* StoreBan

  * belongs_to :store
  * belongs_to :customer_user, class_name: "User"
  * belongs_to :created_by_store_admin_user, class_name: "User"

---

# 4. enum / validation（Phase1確定）

## 4.1 enum

* User

  * enum :role, { customer: 0, cast: 1, store_admin: 2, system_admin: 3 }

* StoreMembership

  * enum :membership_role, { cast: 0, admin: 1 }

* Booth

  * enum :status, { offline: 0, live: 1, away: 2 }

* DrinkOrder

  * enum :status, { pending: 0, consumed: 1, refunded: 2 }

* WalletTransaction

  * enum :kind, { purchase: 0, hold: 1, release: 2, consume: 3, adjustment: 4 }

* StreamSession
  * enum :status, { live: 0, ended: 1 }

* WalletPurchase
  * enum :status, {pending: 0, paid: 1, credited: 2, canceled: 3, failed: 4 }
---

## 4.2 validation（最低限）

* DrinkItem

  * presence :name
  * numericality :price_points, greater_than: 0
  * inclusion :enabled

* Wallet

  * numericality :available_points, greater_than_or_equal_to: 0
  * numericality :reserved_points, greater_than_or_equal_to: 0
  * uniqueness :customer_user_id

* DrinkOrder

  * presence :store_id, :booth_id, :stream_session_id, :customer_user_id, :drink_item_id
  * status 必須
  * consumed_at は consumed時必須（アプリ側 or custom validation）
  * refunded_at は refunded時必須

* Presence

  * presence :joined_at, :last_seen_at

* StoreBan

  * uniqueness :[store_id, customer_user_id]

---

# 5. マイグレーション順序（依存関係順）

1. `users`
2. `stores`
3. `store_memberships`
4. `booths`
5. `booth_casts`
6. `stream_sessions`
7. `presences`
8. `wallets`
9. `wallet_transactions`
10. `drink_items`
11. `drink_orders`
12. `store_ledger_entries`
13. `store_bans`
14. `comments`

> Boothの `current_stream_session_id` は stream_sessions の後に追加するか、外部キー制約を後付けにすると作りやすいです。

---

# 6. Turbo StreamsのView配置（最低限の設計）

## 6.1 顧客：booths#show

* `turbo_stream_from @stream_session, :comments`
* `turbo_stream_from @stream_session, :events`

更新対象DOM（例）

* コメント一覧：`#comments`
* 状態領域：`#booth_status`
* ドリンク演出：`#events`

## 6.2 キャスト：cast/booths#show（バックヤード）

* `turbo_stream_from @stream_session, :comments`
* `turbo_stream_from @stream_session, :events`

更新対象DOM

* 未消化カラム：`#pending_drinks`
* ステータスバー：`#cast_stats`

---

# 7. LP行動分析

## 7.1 対象と正本

* 対象LPは`stores/lp_202607`と`stores/lp_202609`で、内部識別子はそれぞれ`stores_lp_202607`、`stores_lp_202609`とする
* セクション・CTAの許可key、表示名、種別、最下部セクションはLP識別子ごとの設定として保持し、異なるLPのkeyを意図せず受け付けない
* `lp_analytics_visits`が匿名訪問、`lp_analytics_events`が訪問内の行動、`lp_analytics_sheet_exports`が日次出力状態を保持する
* 行動・登録・お問い合わせ実績の正本はRails DBとし、Googleスプレッドシートは匿名の日次集計を共有するための派生データとする
* 分析テーブルには氏名、メールアドレス、電話番号、フォーム本文、IPアドレス、raw User-Agent、cookie値を保存しない
* 店舗登録とお問い合わせの業務レコードは従来のテーブルに保存し、分析イベントからはpolymorphic association（複数種類の完了レコードへの関連）で参照する

## 7.2 匿名訪問

* ブラウザへUUID形式の公開訪問IDを発行し、同じIDでLP表示からフォーム表示・完了までを関連付ける
* 最後の操作から30分以内で、LP・UTM・referral codeが同じ場合は同一訪問を継続する
* 30分を超えた場合、UTMが変わった場合、referral codeが変わった場合、または有効な公開訪問IDがない場合は新規訪問とする
* 対象LPを経由していない通常フォーム流入では、分析訪問やフォーム表示イベントを作成しない
* `LpAnalytics::Visits::ResolveService`が訪問の継続・新規判定を担当し、Controller（リクエストを受ける層）は流入値と現在の公開訪問IDを渡す

## 7.3 イベント記録

* ブラウザイベントAPIは`POST /lp_analytics/events`で受け付け、`LpAnalytics::Events::RecordService`が許可されたイベント種別・値・metadataだけを保存する
* ブラウザイベントにはUUID形式の`browser_event_id`を付け、unique indexにより通信再送を冪等にする
* スクロール、セクション、CTA位置到達は訪問内の`dedupe_key`でも重複を防止する。CTAクリックとFAQ操作は複数回保存できる
* ブラウザ送信は`keepalive`を使い、失敗を画面遷移やフォーム操作へ伝播させない
* Turbo preview / prerenderではLP表示・フォーム表示イベントを送信しない
* フォーム表示時は、Rails session内に遷移元LPと一致する許可済み訪問がある場合だけ計測を有効にする。ブラウザはtab単位の公開訪問IDと遷移元LP識別子を送り、イベントAPIが両者の一致を確認する
* 店舗登録完了とお問い合わせ完了は、業務保存成功後に`LpAnalytics::Completions::RecordService`から記録し、ブラウザやGTMの成功に依存させない
* 分析記録失敗は業務保存をrollbackせず、安全なerror classだけをlogへ残す

### 7.3.1 店舗登録の完了地点

店舗登録は、アカウントとStoreを作る段階、初回店舗設定で情報を保存・公開する段階、サンクスを表示する段階を分ける。

1. `Stores::RegisterStoreAdmin`はStore、store_admin、管理者所属、初期ドリンクを作る。Storeは`published = false`、`onboarding_step = invite_cast`とし、この時点では`store_registration_complete`を記録しない。
2. 登録成功後は新しいstore_adminでログインし、作成したStoreを`current_store`に設定する。許可済みの`from`、UTM、Store IDを`store_registration_pending` sessionへ保存し、`/admin/stores/:store_id/registration_setup/edit`へ遷移する。
3. 初回店舗設定は、pendingのStore ID、`current_store`、管理権限がすべて一致する場合だけ表示・更新できる。通常の店舗情報フォーム、AI店舗情報入力、Cropper.js画像組、`Stores::UpdateService`を再利用する。
4. `Stores::CompleteRegistrationSetup`が店舗情報と画像を保存し、request由来の公開状態を受け付けずサーバー側で`published = true`にする。保存に失敗した場合は非公開状態、pending、旧画像を維持する。
5. 保存・公開成功後だけ、Storeに匿名LP訪問が紐づいていれば`store_registration_complete`を記録する。その後pendingを削除し、Store ID、許可済み`from`、UTMだけを`store_registration_completion` sessionへ移してサンクスへ遷移する。
6. サンクスはcompletionのStore ID、`current_store`、管理権限を検証し、初回表示時にcompletionを消費する。GTMのdataLayerへは完了event、許可済み`from`、UTMだけを渡し、Store ID、User ID、紹介コードは渡さない。
7. サンクス表示後にLP attribution / referral code sessionを削除し、ダッシュボードへ案内する。ダッシュボードでは既存オンボーディングが`invite_cast`から始まる。

初回設定を離脱しても通常管理画面への移動は強制的に禁止しない。通常店舗編集から公開した場合や、pending sessionを失った場合は登録完了イベントを補完しない。初回設定の再開状態を表すDBカラムも追加しないため、このようなStoreは公開状態にかかわらず初回フローのCV未達成として扱う。

## 7.4 集計と管理画面

* system_adminだけが`/system_admin/lp_analytics`と匿名訪問詳細を閲覧できる
* `AnalysisFilter`は今日・過去7日・過去30日・任意期間（最大366日）と、LP・流入元・UTM・端末の絞り込みを扱う
* 対象期間は日本時間の訪問開始日時で判定する。訪問開始後のイベントは、翌日発生分を含めて訪問開始日の実績へ集計する
* `AnalysisQuery`がKPI、連続ファネル、スクロール、セクション、CTA別集計を返す
* 最近のコンバージョンは1ページ20件、最大100件でページングし、訪問をpreloadしてN+1 queryを防ぐ
* 日次集計は`DailyAggregationQuery`が訪問単位のevent集計CTEを作ってから流入・UTM・端末軸でまとめ、複数eventのjoinによる直積を避ける
* 日次集計は主要セクションごとの到達訪問数と、同じ集計行のLP訪問数を分母とする到達率を返す

## 7.5 Googleスプレッドシート出力

* `LpAnalytics::Sheets::ExportRecentDaysJob`を毎日02:20 JSTに起動し、前日を終端とする直近7日を再集計する
* 自動出力は`LP_ANALYTICS_SHEETS_EXPORT_ENABLED`でGoogle Sheets部分だけを無効化できる
* 書込みは`spreadsheets.values.batchUpdate`へまとめ、`aggregation_key`で既存行を更新して重複行を作らない
* 再集計で消えた行を空欄化する場合は対象日とLP識別子の両方を一致させ、同日の別LP行を維持する
* Rails管理header変更時は、完全一致する既知の旧headerだけを新schemaへ移行する。未知のheader不一致、重複key、不完全な管理行は書込みを停止する
* Google API通信中にDB transactionを保持せず、429・5xx・timeoutだけを有限回retryする
* Secret値はAWS Secrets Managerからworker実行時に取得し、Git、環境変数、通常log、Googleスプレッドシートへ出さない
* 詳細な設定・障害復旧は[LP行動分析 Google Sheets連携運用手順](ops/lp_analytics_google_sheets.md)、横断確認は[LP行動分析 横断検証・rollout手順](ops/lp_analytics_validation.md)に従う

---

# 8. Cropper.js画像更新（Phase2目標）

User / Store / Boothの新方式では、1用途につき編集元画像・表示用画像・crop dataを一つの画像組として扱う。Controller（リクエストを受ける層）は認可、strong parameters、Service（業務処理を集約するクラス）呼出し、レスポンスに留める。

* `ImageAttachments::PairValidator`がRails multipartまたは移行処理から受けた2個のJPEG実体、寸法、容量、crop dataを共通検査する。クライアント由来の`sourceBlobId`は保存せず、更新Serviceが確定したBlob IDで付与する
* `ImageAttachments::MultipartPayload`が`image_pair`配下の操作、source、display、JSON文字列のcrop data、編集開始時の4つの期待IDを共通parameter契約として検査する
* Viewは`shared/_image_attachment_editor.html.erb`へ用途別root、`square` / `social`、現在の2画像URL・crop data・期待IDを渡す。共通partialとStimulus Controllerがmultipart項目を生成し、個別ViewやControllerへCropper.js固有parameterを追加しない。再編集用sourceはActive Storage proxy URLで同一originから読み込む
* `ImageAttachments::MultipartUpdateService`が全画像の検査後、`StagedBlobUploadService`で用途別Active Storageへ事前保存し、保存先の存在確認後に`StagedPairUpdateService`へ一体更新を委譲する。1レコードの複数用途を受けた場合も全用途と通常属性を一つのtransactionで更新する
* `Profiles::UpdateService`がUserのavatar / coverを用途別rootから受け取り、通常属性と一体更新する。サーバー互換として既存FilePondのavatar parameterも撤去Issueまでは受け付けるが、通常プロフィールViewは送信しない。新旧parameterが同時なら二重更新せず拒否する
* `Stores::UpdateService`がStoreの`thumbnail`画像組と通常属性を一体更新する。通常Store管理Viewは既存FilePond parameterを送信せず、新方式の`image_pair`と旧`store[thumbnail]` / `store[remove_thumbnail]`が同時なら二重更新せず拒否する
* `Booths::UpdateService`がBoothの`thumbnail_image`画像組、通常属性、初回キャスト紐づけを一つのtransactionで更新する。通常Booth作成・編集Viewは既存FilePond parameterを送信せず、新方式の`image_pair`と旧`booth[thumbnail_image]` / `booth[remove_thumbnail_image]`が同時なら二重更新せず拒否する
* Userプロフィール、Store管理、Booth作成・編集フォームの画像変更時は`image_pair_form_controller`が`ImagePairMultipartClient`で画像組と通常属性を一回だけ送信し、45秒超過・通信失敗時は自動再送せず入力を保持する。成功レスポンスの同一origin遷移先だけを採用する
* multipart全体はPumaと`MultipartBodyLimit`で26MiBに制限し、`Content-Length`欠落・虚偽も実読込量で拒否する。ブラウザは`ImagePairMultipartClient`で45秒を上限とし、自動再送しない
* レコードロック下で編集開始時のattachment ID・blob IDを照合し、古い画面による上書きを拒否する
* 新規・差し替えは編集元・表示用・crop data、再編集は表示用・crop data、削除は3点すべてを一つのDB transactionで更新する
* transaction失敗時は旧状態を維持し、新規Blobだけを清掃する。成功後に参照されなくなった旧Blobを非同期清掃する
* Controllerがモデルごとに画像処理を再実装せず、通常属性を含む関連処理はServiceへblock等で委譲して同じtransactionに含める
* 既存画像移行は通常更新と同じ保存Serviceを使い、dry-run、ID範囲、途中再開、冪等性、期待ID照合を備えた専用Service / taskから呼び出す
* `ImageAttachments::LegacyMigrationService`は移行前の表示添付をattachment ID順に処理し、`LegacyPairBuilder`で通常経路と同じ上限・検査を通した一時Blobを生成して`StagedPairUpdateService`へ渡す。Userはcoverを先に確定し、失敗時は共通生成元の移行前avatarを維持する。taskのapplyは件数上限、範囲または期待ID、確認文字列、実行Git SHAを必須とする

添付名、crop schema、ブラウザ正規化、上限、移行順、撤去条件は [Cropper.js画像アップロード確定設計](design/image_upload_cropper_architecture.md) を正とする。現行FilePond経路は通常画面の切替と既存画像移行が完了するまで維持する。
