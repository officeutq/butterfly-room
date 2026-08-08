# frozen_string_literal: true

class AccountWithdrawalsController < ApplicationController
  before_action :authenticate_user!
  before_action :reject_system_admin!

  def show
    @errors = []
  end

  def destroy
    @errors = validation_errors
    return render(:show, status: :unprocessable_entity) if @errors.any?

    return unless perform_withdrawal

    sign_out(:user)
    flash[:notice] = "退会が完了しました"

    if turbo_frame_request?
      render :completed, layout: false
    else
      redirect_to new_user_session_path, status: :see_other
    end
  end

  private

  def reject_system_admin!
    head :forbidden if current_user.system_admin?
  end

  def validation_errors
    errors = []
    attributes = withdrawal_params

    unless current_user.valid_password?(attributes[:current_password].to_s)
      errors << "現在のパスワードが正しくありません"
    end

    unless ActiveModel::Type::Boolean.new.cast(attributes[:confirmed])
      errors << "退会に関する注意事項を確認してください"
    end

    errors
  end

  def perform_withdrawal
    Accounts::WithdrawalService.new(user: current_user).call!
    true
  rescue Accounts::WithdrawalService::NotAllowed
    head :forbidden
    false
  rescue StandardError
    @errors = [ "退会処理を完了できませんでした。時間をおいて、もう一度お試しください。" ]
    render :show, status: :unprocessable_entity
    false
  end

  def withdrawal_params
    params
      .fetch(:account_withdrawal, ActionController::Parameters.new)
      .permit(:current_password, :confirmed)
  end
end
