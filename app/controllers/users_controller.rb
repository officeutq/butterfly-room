# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = User.where(deleted_at: nil).find(params[:id])

    @cast_booths = []
    @admin_stores = []
    @favorite_booth_ids = Set.new
    @favorite_store_ids = Set.new
    @favorite_user_ids = Set.new

    if @user.cast?
      @cast_booths =
        @user
          .cast_booths
          .active
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

      @favorite_booth_ids =
        current_user.favorite_booths.where(booth_id: booth_ids).pluck(:booth_id).to_set

      @favorite_store_ids =
        current_user.favorite_stores.where(store_id: store_ids).pluck(:store_id).to_set

      @favorite_user_ids =
        current_user.favorite_users.where(target_user_id: cast_user_ids).pluck(:target_user_id).to_set
    end

    if @user.store_admin?
      @admin_stores =
        @user
          .store_memberships
          .where(membership_role: :admin)
          .includes(:store)
          .map(&:store)

      store_ids = @admin_stores.map(&:id)

      @favorite_store_ids =
        @favorite_store_ids.merge(
          current_user.favorite_stores.where(store_id: store_ids).pluck(:store_id).to_set
        )
    end
  end
end
