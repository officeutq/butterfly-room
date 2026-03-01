# frozen_string_literal: true

module StoreAdmins
  class RegistrationsController < ApplicationController
    skip_before_action :authenticate_user!, raise: false

    before_action :require_token!

    def new
      @form = StoreAdmins::RegistrationForm.new(email: params[:email].to_s)
    end

    def create
      @form = StoreAdmins::RegistrationForm.new(registration_params)

      if @form.save
        sign_in(@form.user) # Devise
        redirect_to store_admin_invitation_path(@token),
                    notice: "store_admin アカウントを作成しました。招待を承認してください。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def require_token!
      @token = params[:token].to_s
      invitation = StoreAdminInvitation.find_by_token(@token)
      head :not_found if invitation.blank?
    end

    def registration_params
      params.require(:store_admin_registration).permit(
        :email,
        :password,
        :password_confirmation
      )
    end
  end
end
