# frozen_string_literal: true

class StoresController < ApplicationController
  include StoreBanGuard

  skip_before_action :authenticate_user!, only: %i[show]
  before_action :clear_guest_unauthenticated_alert, only: %i[show]
  before_action :set_store, only: %i[show]
  before_action :reject_banned_customer_for_store!, only: %i[show]

  def show
    @booths =
      @store
        .booths
        .active
        .includes(
          :current_stream_session,
          { booth_casts: :cast_user },
          { thumbnail_image_attachment: :blob }
        )
        .order(:id)

    if user_signed_in?
      @store_favorited = current_user.favorite_stores.exists?(store_id: @store.id)
      @favorite_booth_ids =
        current_user.favorite_booths.where(booth_id: @booths.map(&:id)).pluck(:booth_id).to_set

      cast_user_ids = @booths.map(&:primary_cast_user_id).compact.uniq
      @favorite_user_ids =
        current_user.favorite_users.where(target_user_id: cast_user_ids).pluck(:target_user_id).to_set
    else
      @store_favorited = false
      @favorite_booth_ids = Set.new
      @favorite_user_ids = Set.new
    end

    set_store_meta_tags
  end

  private

  def set_store
    @store = Store.published.with_attached_thumbnail.find(params[:id])
  end

  def reject_banned_customer_for_store!
    reject_banned_customer!(store: @store)
  end

  def set_store_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    description = Stores::MetaDescriptionBuilder.call(@store)
    og_image =
      if @store.thumbnail.attached?
        url_for(@store.thumbnail)
      else
        view_context.image_url("booth-share-ogp.jpg")
      end

    set_meta_tags(
      title: @store.name,
      description: description,
      noindex: false,
      nofollow: false,
      canonical: store_url(@store),
      og: {
        title: "#{@store.name} | #{brand_name}",
        description: description,
        type: "website",
        url: store_url(@store),
        image: og_image
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end
end
