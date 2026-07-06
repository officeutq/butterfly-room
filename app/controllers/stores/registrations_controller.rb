# frozen_string_literal: true

module Stores
  class RegistrationsController < ApplicationController
    STORE_REGISTRATION_FROM_STORES_LP = "stores_lp"
    STORE_REGISTRATION_FROM_STORES_LP_202607 = "stores_lp_202607"
    STORE_REGISTRATION_FROM_SOURCES = [
      STORE_REGISTRATION_FROM_STORES_LP,
      STORE_REGISTRATION_FROM_STORES_LP_202607
    ].freeze

    skip_before_action :authenticate_user!, raise: false
    before_action :set_store_registration_back_path, only: %i[new create]

    def new
      @form = Stores::RegistrationForm.new(referral_code: params[:ref].to_s)
    end

    def create
      @form = Stores::RegistrationForm.new(registration_params)

      if @form.save
        sign_in(@form.user) # Devise
        session[:current_store_id] = @form.store.id
        session.delete(:current_booth_id)

        redirect_to edit_admin_store_path(@form.store), notice: "店舗登録が完了しました。続けて店舗情報を入力してください。"
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

    def set_store_registration_back_path
      @store_registration_from = permitted_store_registration_from
      @store_registration_back_path =
        case @store_registration_from
        when STORE_REGISTRATION_FROM_STORES_LP_202607
          stores_lp_202607_path
        else
          stores_lp_path
        end
      @store_registration_form_path = store_registration_form_path(@store_registration_from)
    end

    def permitted_store_registration_from
      from = params[:from].presence
      return from if STORE_REGISTRATION_FROM_SOURCES.include?(from)

      nil
    end

    def store_registration_form_path(from)
      return stores_registrations_path if from.blank?

      stores_registrations_path(from: from)
    end
  end
end
