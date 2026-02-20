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
  end
end
