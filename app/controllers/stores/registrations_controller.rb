# frozen_string_literal: true

module Stores
  class RegistrationsController < ApplicationController
    skip_before_action :authenticate_user!, raise: false

    def new
      @form = Stores::RegistrationForm.new(referral_code: params[:ref].to_s)
    end

    def create
      @form = Stores::RegistrationForm.new(registration_params)

      if @form.save
        sign_in(@form.user) # Devise
        redirect_to dashboard_path, notice: "店舗登録が完了しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def registration_params
      params.require(:store_registration).permit(
        :store_name,
        :email,
        :password,
        :password_confirmation,
        :referral_code
      )
    end
  end
end
