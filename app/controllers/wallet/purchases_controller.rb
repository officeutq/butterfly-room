class Wallet::PurchasesController < ApplicationController
  before_action :authenticate_user!

  def new
    @return_to = safe_return_path(params[:return_to])
    render :new
  end

  def create
    return_to = safe_return_path(params[:return_to])

    checkout_url = Wallets::CreateCheckoutService.new(
      customer_user: current_user,
      plan_key: params.require(:plan_key).to_s,
      booth_id: nil, # 戻り先は return_to で管理
      return_to: return_to,
      base_url: request.base_url
    ).call!

    redirect_to checkout_url, allow_other_host: true
  rescue ArgumentError => e
    # 未知 plan_key など
    redirect_to(return_to.presence || root_path,
                alert: e.message,
                status: :unprocessable_entity)
  end

  private

  # CheckoutController と同じ安全ルール（同一オリジンの相対パスのみ許可）
  def safe_return_path(path)
    return nil if path.blank?
    path = path.to_s
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//")

    path
  end
end
