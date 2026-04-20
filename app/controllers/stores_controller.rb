# frozen_string_literal: true

class StoresController < ApplicationController
  include StoreBanGuard

  before_action -> { require_at_least!(:customer) }
  before_action :set_store, only: %i[show]
  before_action :reject_banned_customer_for_store!, only: %i[show]

  def show
    @booths =
      @store
        .booths
        .active
        .includes(:cast_users)
        .order(:id)

    @store_favorited = current_user.favorite_stores.exists?(store_id: @store.id)

    cast_user_ids = @booths.map(&:primary_cast_user_id).compact.uniq
    @favorite_user_ids =
      current_user.favorite_users.where(target_user_id: cast_user_ids).pluck(:target_user_id).to_set
  end

  private

  def set_store
    @store = Store.find(params[:id])
  end

  def reject_banned_customer_for_store!
    reject_banned_customer!(store: @store)
  end
end
