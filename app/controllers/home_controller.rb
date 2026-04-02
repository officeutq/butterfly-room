# frozen_string_literal: true

class HomeController < ApplicationController
  def show
    @mode = params[:mode].to_s
    @mode = "booths" unless %w[booths stores].include?(@mode)

    @q = params[:q].to_s.strip
    q_like =
      if @q.present?
        escaped = ActiveRecord::Base.sanitize_sql_like(@q)
        "%#{escaped}%"
      end

    if @mode == "stores"
      @booths = Booth.none

      stores = Store.all

      # store name で絞り込み
      stores = stores.where("stores.name ILIKE ?", q_like) if q_like.present?

      active_booth_counts =
        Booth.active
             .select("booths.store_id AS store_id, COUNT(*) AS active_booths_count")
             .group("booths.store_id")

      online_flags =
        Booth.active
             .where(status: %i[live away])
             .select("booths.store_id AS store_id, 1 AS online_priority")
             .group("booths.store_id")

      stores =
        stores
          .joins("LEFT JOIN (#{active_booth_counts.to_sql}) active_booth_counts ON active_booth_counts.store_id = stores.id")
          .joins("LEFT JOIN (#{online_flags.to_sql}) online_flags ON online_flags.store_id = stores.id")
          .order(
            Arel.sql("COALESCE(online_flags.online_priority, 0) DESC"),
            Arel.sql("COALESCE(active_booth_counts.active_booths_count, 0) DESC"),
            id: :desc
          )
          .limit(30)

      # customer はBAN店舗を除外（現状踏襲）
      if user_signed_in? && current_user.customer?
        banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
        stores = stores.where.not(id: banned_store_ids)
      end

      @stores = stores

      # favorites（表示対象だけ）
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
    @stores = Store.none

    booths = Booth.active

    # current_stream_session.started_at を order で使うため JOIN
    booths =
      booths.joins(<<~SQL)
        LEFT JOIN stream_sessions current_ss
          ON current_ss.id = booths.current_stream_session_id
      SQL

    # booth name で絞り込み（仕様どおり stores.name は対象外）
    booths = booths.where("booths.name ILIKE ?", q_like) if q_like.present?

    # online（live/away）優先
    online_order =
      "CASE WHEN booths.status IN (#{Booth.statuses[:live]}, #{Booth.statuses[:away]}) THEN 1 ELSE 0 END"

    booths =
      booths
        .includes(
          :store,
          :current_stream_session,
          { booth_casts: :cast_user },
          thumbnail_image_attachment: :blob
        )
        .order(
          Arel.sql("#{online_order} DESC"),
          Arel.sql("current_ss.started_at DESC NULLS LAST"),
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
