# frozen_string_literal: true

class UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[show]

  def show
    @user = visible_users.find(params[:id])

    @cast_booths = []
    @admin_stores = []
    @favorite_booth_ids = Set.new
    @favorite_store_ids = Set.new
    @favorite_user_ids = Set.new
    @user_favorited =
      user_signed_in? && current_user.favorite_users.exists?(target_user: @user)

    if @user.cast?
      @cast_booths =
        @user
          .cast_booths
          .active
          .in_published_stores
          .includes(
            :store,
            :current_stream_session,
            { booth_casts: :cast_user },
            { thumbnail_image_attachment: :blob }
          )
          .order(:id)

      booth_ids = @cast_booths.map(&:id)
      store_ids = @cast_booths.map(&:store_id).uniq
      cast_user_ids = @cast_booths.map(&:primary_cast_user_id).compact.uniq

      if user_signed_in?
        @favorite_booth_ids =
          current_user.favorite_booths.where(booth_id: booth_ids).pluck(:booth_id).to_set

        @favorite_store_ids =
          current_user.favorite_stores.where(store_id: store_ids).pluck(:store_id).to_set

        @favorite_user_ids =
          current_user.favorite_users.where(target_user_id: cast_user_ids).pluck(:target_user_id).to_set
      end
    end

    if @user.store_admin?
      @admin_stores =
        @user
          .store_memberships
          .where(membership_role: :admin)
          .joins(:store)
          .merge(Store.published)
          .includes(:store)
          .map(&:store)

      store_ids = @admin_stores.map(&:id)

      if user_signed_in?
        @favorite_store_ids =
          @favorite_store_ids.merge(
            current_user.favorite_stores.where(store_id: store_ids).pluck(:store_id).to_set
          )
      end
    end
  end

  private

  def visible_users
    return User.active if user_signed_in?

    User.public_profiles
  end
end
