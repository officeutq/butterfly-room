# frozen_string_literal: true

class StoreContactSubmissionsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  before_action :redirect_authenticated_user

  def new
    @store_contact_submission = StoreContactSubmission.new
    set_store_contact_submission_meta_tags
  end

  def create
    StoreContactSubmissions::CreateService.new(
      attributes: store_contact_submission_params
    ).call

    redirect_to stores_contact_path,
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
