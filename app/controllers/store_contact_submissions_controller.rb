# frozen_string_literal: true

class StoreContactSubmissionsController < ApplicationController
  STORE_CONTACT_FROM_STORES_LP = "stores_lp"
  STORE_CONTACT_FROM_STORES_LP_202607 = "stores_lp_202607"
  STORE_CONTACT_FROM_SOURCES = [
    STORE_CONTACT_FROM_STORES_LP,
    STORE_CONTACT_FROM_STORES_LP_202607
  ].freeze

  skip_before_action :authenticate_user!, raise: false
  before_action :enable_gtm, only: %i[new create thanks]
  before_action :redirect_authenticated_user
  before_action :set_store_contact_back_path, only: %i[new create]

  def new
    @store_contact_submission = StoreContactSubmission.new
    set_store_contact_submission_meta_tags
  end

  def create
    StoreContactSubmissions::CreateService.new(
      attributes: store_contact_submission_params
    ).call

    session[:store_contact_completion] =
      tracking_session_payload(from: @store_contact_from, utm_params: @store_contact_utm_params)
        .merge("completed" => true)

    redirect_to store_contact_thanks_path(@store_contact_from, @store_contact_utm_params)
  rescue ActiveRecord::RecordInvalid => e
    @store_contact_submission = e.record
    set_store_contact_submission_meta_tags
    render :new, status: :unprocessable_entity
  end

  def thanks
    @store_contact_completion = session.delete(:store_contact_completion)

    if @store_contact_completion.blank?
      redirect_to store_contact_form_path(permitted_store_contact_from, sanitized_utm_params)
      return
    end

    @store_contact_from = permitted_store_contact_from(@store_contact_completion)
    @store_contact_back_path = store_contact_back_path(@store_contact_from)
    @store_contact_utm_params = sanitized_utm_params(@store_contact_completion)

    set_store_contact_thanks_meta_tags
  end

  private

  def redirect_authenticated_user
    return unless user_signed_in?

    redirect_to dashboard_path, alert: "ログイン中は店舗向けお問い合わせフォームを利用できません。"
  end

  def store_contact_submission_params
    params.require(:store_contact_submission).permit(
      :name,
      :store_name,
      :email,
      :phone_number,
      :body,
      :contactable_time
    )
  end

  def set_store_contact_back_path
    @store_contact_from = permitted_store_contact_from
    @store_contact_utm_params = sanitized_utm_params
    @store_contact_back_path = store_contact_back_path(@store_contact_from)
    @store_contact_form_path = store_contact_form_path(@store_contact_from, @store_contact_utm_params)
  end

  def permitted_store_contact_from(source = params)
    from = source[:from].presence || source["from"].presence
    return from if STORE_CONTACT_FROM_SOURCES.include?(from)

    nil
  end

  def store_contact_back_path(from)
    case from
    when STORE_CONTACT_FROM_STORES_LP_202607
      stores_lp_202607_path
    else
      stores_lp_path
    end
  end

  def store_contact_form_path(from, utm_params = {})
    query = tracking_query_params(from:, utm_params:)
    return stores_contact_path if query.blank?

    stores_contact_path(query)
  end

  def store_contact_thanks_path(from, utm_params)
    query = tracking_query_params(from:, utm_params:)
    return stores_contact_thanks_path if query.blank?

    stores_contact_thanks_path(query)
  end

  def set_store_contact_submission_meta_tags
    set_meta_tags(
      title: "店舗向けお問い合わせ",
      description: "Butterflyveの導入を検討している店舗向けのお問い合わせフォームです。",
      noindex: false,
      nofollow: false,
      canonical: stores_contact_url
    )
  end

  def set_store_contact_thanks_meta_tags
    set_meta_tags(
      title: "店舗向けお問い合わせ完了",
      description: "Butterflyveの店舗向けお問い合わせ受付完了ページです。",
      noindex: true,
      nofollow: true,
      canonical: stores_contact_thanks_url
    )
  end
end
