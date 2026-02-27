# frozen_string_literal: true

module Casts
  class RegistrationsController < ApplicationController
    skip_before_action :authenticate_user!, raise: false

    before_action :require_token!

    def new
      @form = Casts::RegistrationForm.new(email: params[:email].to_s)
    end

    def create
      @form = Casts::RegistrationForm.new(registration_params)

      if @form.save
        sign_in(@form.user) # Devise
        redirect_to cast_invitation_path(@token), notice: "cast アカウントを作成しました。招待を承認してください。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def require_token!
      @token = params[:token].to_s
      invitation = StoreCastInvitation.find_by_token(@token)
      head :not_found if invitation.blank?
    end

    def registration_params
      params.require(:cast_registration).permit(
        :email,
        :password,
        :password_confirmation
      )
    end
  end
end
