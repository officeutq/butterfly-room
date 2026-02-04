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


---

## 1.1. ディレクトリ/クラス構成

```
app/
  controllers/
    application_controller.rb
    booths_controller.rb
    checkout_controller.rb
    home_controller.rb
    stream_sessions_controller.rb
    admin/
      base_controller.rb
      booths_controller.rb
      casts_controller.rb
      dashboard_controller.rb
      drink_items_controller.rb
      metrics_controller.rb
      store_bans_controller.rb
    cast/
      base_controller.rb
      booths_controller.rb
      drink_orders_controller.rb
      stream_sessions_controller.rb
      booths/
        stream_sessions_controller.rb
    concerns/
      store_ban_guard.rb
    stream_sessions/
      comments_controller.rb
      drink_orders_controller.rb
      ivs_participant_tokens_controller.rb
      presences_controller.rb
    wallet/
      purchases_controller.rb
    webhooks/
      stripe_controller.rb

  helpers/
    application_helper.rb
    admin/
      metrics_helper.rb

  javascript/
    application.js
    controllers/
      application.js
      camera_preview_controller.js
      index.js
      ivs_publisher_controller.js
      ivs_viewer_controller.js
      presence_poll_controller.js
      stream_debug_controller.js

  models/
    application_record.rb
    booth_cast.rb
    booth.rb
    comment.rb
    drink_item.rb
    drink_order.rb
    presence.rb
    store_ban.rb
    store_ledger_entry.rb
    store_membership.rb
    store.rb
    stream_session.rb
    stripe_webhook_event.rb
    user.rb
    wallet_purchase.rb
    wallet_transaction.rb
    wallet.rb

  notifiers/
    comment_notifier.rb
    drink_order_notifier.rb
    stream_session_notifier.rb

  queries/
    cast_metrics_query.rb
    pending_drink_orders_query.rb（未実装）
    presence_count_query.rb（未実装）

  services/
    authorization/
      application_policy.rb
      booth_policy.rb
      store_ban_checker.rb
      stream_session_policy.rb
    drink_orders/
      consume_service.rb
      create_service.rb
      fifo_guard.rb
      refund_service.rb
    ivs/
      client.rb
      create_participant_token_service.rb
    presence/
      ping_service.rb
      summary_service.rb
    stream_sessions/
      end_service.rb
      ensure_ivs_stage_service.rb
      start_service.rb
      status_service.rb
      comments/
        create_service.rb
    wallets/
      apply_purchase_from_stripe_service.rb
      consume_service.rb
      create_checkout_service.rb
      hold_service.rb
      purchase_credit_service.rb（未実装）
      release_service.rb

    views/
      admin/
        casts/
          index.html.erb
        dashboard/
          show.html.erb
        drink_items/
          _form.html.erb
          index.html.erb
        metrics/
          cast.html.erb
        store_bans/
          index.html.erb
      booths/
        show.html.erb
      cast/
        booths/
          index.html.erb
          show.html.erb
        stream_sessions/
          _ended.html.erb
          _pending_drink_orders.html.erb
      checkout/
        return.html.erb
      comments/
        _comment.html.erb
      home/
        show.html.erb
      layouts/
        application.html.erb
      stream_sessions/
        _ended.html.erb
        _ivs_viewer.html.erb
        _pending_drink_orders.html.erb
        _viewer_ended.html.erb
        comments/
          _form.html.erb

config/
  ...
  routes.rb
  ...
  environments/
    ...
  initializers/
    ...
    stripe.rb
  locales/
    ...
```

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
  get  "/home_feed", to: "home#feed" # JSONでもHTMLでもOK

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
    resources :booths, only: %i[index show] do
      resources :stream_sessions, only: %i[create], module: :booths
      patch :status, on: :member # live/away切替
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

    resources :booths, only: %i[index create update]
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
