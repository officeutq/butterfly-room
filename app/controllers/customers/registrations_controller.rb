# frozen_string_literal: true

module Customers
  class RegistrationsController < ApplicationController
    skip_before_action :authenticate_user!, raise: false

    def new
      @form = Customers::RegistrationForm.new
    end

    def create
      @form = Customers::RegistrationForm.new(registration_params)

      if @form.save
        sign_in(@form.user) # Devise
        redirect_to stored_location_for(:user) || edit_profile_path,
                    notice: "アカウントを作成しました。プロフィールを作成してください。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def registration_params
      params.require(:customer_registration).permit(
        :email,
        :password,
        :password_confirmation
      )
    end
  end
end
