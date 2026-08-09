# frozen_string_literal: true

module Stores
  class RegistrationsController < ApplicationController
    STORE_REGISTRATION_FROM_STORES_LP = "stores_lp"
    STORE_REGISTRATION_FROM_STORES_LP_202607 = "stores_lp_202607"
    STORE_REGISTRATION_FROM_SOURCES = [
      STORE_REGISTRATION_FROM_STORES_LP,
      STORE_REGISTRATION_FROM_STORES_LP_202607
    ].freeze

    skip_before_action :authenticate_user!, only: %i[new create], raise: false
    before_action :enable_gtm, only: %i[new create thanks]
    before_action :set_store_registration_back_path, only: %i[new create]

    def new
      @form = Stores::RegistrationForm.new(referral_code: params[:ref].to_s)
    end

    def create
      @form = Stores::RegistrationForm.new(registration_params)

      if @form.save
        completion_payload = completion_tracking_payload(from: @store_registration_from)

        sign_in(@form.user) # Devise
        session[:current_store_id] = @form.store.id
        session.delete(:current_booth_id)
        session[:store_registration_completion] =
          completion_payload
            .merge("store_id" => @form.store.id)

        redirect_to store_registration_thanks_path(@store_registration_from)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def thanks
      @store_registration_completion = session.delete(:store_registration_completion)
      @store = store_from_registration_completion(@store_registration_completion)

      unless valid_registration_completion_store?(@store)
        redirect_to invalid_registration_completion_redirect_path
        return
      end

      @store_registration_from = permitted_store_registration_from(@store_registration_completion)
      @store_registration_gtm_event = gtm_conversion_event_payload(
        event: "store_registration_complete",
        completion: @store_registration_completion
      )

      delete_store_lp_202607_attribution
      delete_store_lp_202607_ref

      set_store_registration_thanks_meta_tags
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
          stores_lp_202607_return_path
        else
          stores_lp_path
        end
      @store_registration_form_path = store_registration_form_path(
        @store_registration_from
      )
      @lp_analytics_form_event_type = "store_registration_form_view" if lp_analytics_form_tracking?
    end

    def lp_analytics_form_tracking?
      @store_registration_from == STORE_REGISTRATION_FROM_STORES_LP_202607 &&
        lp_analytics_visit_public_id.present?
    end

    def permitted_store_registration_from(source = params)
      from = source[:from].presence || source["from"].presence
      return from if STORE_REGISTRATION_FROM_SOURCES.include?(from)

      nil
    end

    def store_registration_form_path(from)
      query = tracking_query_params(from:)
      return stores_registrations_path if query.blank?

      stores_registrations_path(query)
    end

    def store_registration_thanks_path(from)
      query = tracking_query_params(from:)
      return stores_registration_thanks_path if query.blank?

      stores_registration_thanks_path(query)
    end

    def store_from_registration_completion(completion)
      return nil if completion.blank?

      store_id = completion[:store_id].presence || completion["store_id"].presence
      Store.find_by(id: store_id)
    end

    def valid_registration_completion_store?(store)
      return false if store.blank?
      return false unless session[:current_store_id].to_i == store.id
      return true if current_user.system_admin?

      current_user.admin_of_store?(store.id)
    end

    def invalid_registration_completion_redirect_path
      store = current_store_for_registration_completion
      return edit_admin_store_path(store) if store.present?

      dashboard_path
    end

    def current_store_for_registration_completion
      store = Store.find_by(id: session[:current_store_id])
      return nil if store.blank?
      return store if current_user.system_admin?
      return store if current_user.admin_of_store?(store.id)

      nil
    end

    def set_store_registration_thanks_meta_tags
      set_meta_tags(
        title: "店舗登録完了",
        description: "Butterflyveの店舗登録完了ページです。",
        noindex: true,
        nofollow: true,
        canonical: stores_registration_thanks_url
      )
    end
  end
end
