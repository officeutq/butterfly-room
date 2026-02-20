# frozen_string_literal: true

class HomeController < ApplicationController
  def show
    booths = Booth.active
                 .includes(
                   :store,
                   { booth_casts: :cast_user },
                   thumbnail_image_attachment: :blob
                 )
                 .order(updated_at: :desc, id: :desc)
                 .limit(60)

    # 可能な範囲で予防（ただし最終防衛は BoothsController#show の StoreBanGuard が担保）
    if user_signed_in? && current_user.customer?
      banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
      booths = booths.where.not(store_id: banned_store_ids)
    end

    @booths = booths

    # --- store list (minimal) ---
    stores =
      Store
        .where(id: Booth.active.select(:store_id)) # active booth を持つ store だけ
        .order(updated_at: :desc, id: :desc)
        .limit(30)

    if user_signed_in? && current_user.customer?
      banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
      stores = stores.where.not(id: banned_store_ids)
    end

    @stores = stores

    # --- favorites preloading for home (avoid N+1) ---
    if user_signed_in?
      @favorite_booth_ids =
        current_user.favorite_booths.where(booth_id: @booths.select(:id)).pluck(:booth_id).to_set

      @favorite_store_ids =
        current_user.favorite_stores.where(store_id: @stores.select(:id)).pluck(:store_id).to_set
    else
      @favorite_booth_ids = Set.new
      @favorite_store_ids = Set.new
    end
  end
end
