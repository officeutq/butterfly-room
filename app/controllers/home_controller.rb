# frozen_string_literal: true

class HomeController < ApplicationController
  def show
    @mode = params[:mode].to_s
    @mode = "booths" unless %w[booths stores users].include?(@mode)

    @q = params[:q].to_s.strip
    q_like =
      if @q.present?
        escaped = ActiveRecord::Base.sanitize_sql_like(@q)
        "%#{escaped}%"
      end

    @booths = Booth.none
    @stores = Store.none
    @users = User.none

    if @mode == "users"
      users =
        User
          .where(role: %i[cast store_admin])

      users = users.where("users.display_name ILIKE ?", q_like) if q_like.present?

      @users =
        users
          .order(
            Arel.sql("CASE WHEN users.display_name IS NULL OR btrim(users.display_name) = '' THEN 1 ELSE 0 END ASC"),
            id: :desc
          )
          .limit(30)

      @favorite_booth_ids = Set.new
      @favorite_store_ids = Set.new
      return
    end

    if @mode == "stores"
      stores = Store.all

      stores = stores.where("stores.name ILIKE ?", q_like) if q_like.present?

      # --- online: MAX(started_at) ---
      online_started_at =
        Booth.active
            .where(status: %i[live away])
            .joins("INNER JOIN stream_sessions ss ON ss.id = booths.current_stream_session_id")
            .select("booths.store_id AS store_id, MAX(ss.started_at) AS max_started_at")
            .group("booths.store_id")

      # --- offline/standby: MAX(last_online_at) ---
      last_online =
        Booth.active
            .select("booths.store_id AS store_id, MAX(booths.last_online_at) AS max_last_online_at")
            .group("booths.store_id")

      stores =
        stores
          .joins("LEFT JOIN (#{online_started_at.to_sql}) online ON online.store_id = stores.id")
          .joins("LEFT JOIN (#{last_online.to_sql}) last_online ON last_online.store_id = stores.id")
          .order(
            Arel.sql("CASE WHEN online.max_started_at IS NOT NULL THEN 1 ELSE 0 END DESC"),
            Arel.sql("online.max_started_at DESC NULLS LAST"),
            Arel.sql("last_online.max_last_online_at DESC NULLS LAST"),
            id: :desc
          )
          .limit(30)

      if user_signed_in? && current_user.customer?
        banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
        stores = stores.where.not(id: banned_store_ids)
      end

      @stores = stores

      if user_signed_in?
        @favorite_store_ids =
          current_user.favorite_stores.where(store_id: @stores.select(:id)).pluck(:store_id).to_set
      else
        @favorite_store_ids = Set.new
      end

      @favorite_booth_ids = Set.new
      return
    end

    # --- mode=booths ---
    booths = Booth.active

    booths =
      booths.joins(<<~SQL)
        LEFT JOIN stream_sessions current_ss
          ON current_ss.id = booths.current_stream_session_id
      SQL

    booths = booths.where("booths.name ILIKE ?", q_like) if q_like.present?

    online_order =
      "CASE WHEN booths.status IN (#{Booth.statuses[:live]}, #{Booth.statuses[:away]}) THEN 1 ELSE 0 END"

    booths =
      booths
        .order(
          Arel.sql("#{online_order} DESC"),
          Arel.sql("
            CASE
              WHEN booths.status IN (#{Booth.statuses[:live]}, #{Booth.statuses[:away]})
              THEN current_ss.started_at
            END DESC NULLS LAST
          "),
          Arel.sql("booths.last_online_at DESC NULLS LAST"),
          id: :desc
        )
        .limit(60)

    # customer はBAN店舗を除外（現状踏襲）
    if user_signed_in? && current_user.customer?
      banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
      booths = booths.where.not(store_id: banned_store_ids)
    end

    @booths = booths

    # favorites（表示対象だけ）
    if user_signed_in?
      @favorite_booth_ids =
        current_user.favorite_booths.where(booth_id: @booths.select(:id)).pluck(:booth_id).to_set

      @favorite_store_ids =
        current_user.favorite_stores.where(store_id: @booths.select(:store_id)).pluck(:store_id).to_set
    else
      @favorite_booth_ids = Set.new
      @favorite_store_ids = Set.new
    end
  end
end
