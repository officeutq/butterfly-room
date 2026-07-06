# frozen_string_literal: true

class StoreContactSubmissionsController < ApplicationController
  STORE_CONTACT_FROM_STORES_LP = "stores_lp"
  STORE_CONTACT_FROM_STORES_LP_202607 = "stores_lp_202607"
  STORE_CONTACT_FROM_SOURCES = [
    STORE_CONTACT_FROM_STORES_LP,
    STORE_CONTACT_FROM_STORES_LP_202607
  ].freeze

  skip_before_action :authenticate_user!, raise: false
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

    redirect_to @store_contact_form_path,
      notice: "お問い合わせを受け付けました。内容を確認のうえ、担当者よりご連絡いたします。"
  rescue ActiveRecord::RecordInvalid => e
    @store_contact_submission = e.record
    set_store_contact_submission_meta_tags
    render :new, status: :unprocessable_entity
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
    @store_contact_back_path =
      case @store_contact_from
      when STORE_CONTACT_FROM_STORES_LP_202607
        stores_lp_202607_path
      else
        stores_lp_path
      end
    @store_contact_form_path = store_contact_form_path(@store_contact_from)
  end

  def permitted_store_contact_from
    from = params[:from].presence
    return from if STORE_CONTACT_FROM_SOURCES.include?(from)

    nil
  end

  def store_contact_form_path(from)
    return stores_contact_path if from.blank?

    stores_contact_path(from: from)
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
end
