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
  end

  private

  def set_store
    @store = Store.find(params[:id])
  end

  def reject_banned_customer_for_store!
    reject_banned_customer!(store: @store)
  end
end
