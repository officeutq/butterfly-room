class Wallet::PurchasesController < ApplicationController
  before_action :authenticate_user!

  def create
    checkout_url = Wallets::CreateCheckoutService.new(
      customer_user: current_user,
      points: params.require(:points).to_i,
      booth_id: nil, # 戻り先は return_to で管理
      return_to: params[:return_to],
      base_url: request.base_url
    ).call!

    redirect_to checkout_url, allow_other_host: true
  end
end
