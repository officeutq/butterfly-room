class Wallet::PurchasesController < ApplicationController
  before_action :authenticate_user!

  def create
    checkout_url = Wallets::CreateCheckoutService.new(
      customer_user: current_user,
      points: params.require(:points).to_i,
      booth_id: params[:booth_id],
      base_url: request.base_url
    ).call!

    redirect_to checkout_url, allow_other_host: true
  end
end
