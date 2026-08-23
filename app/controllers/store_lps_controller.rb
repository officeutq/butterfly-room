# frozen_string_literal: true

class StoreLpsController < ApplicationController
  STORE_LP_202607_FROM = "stores_lp_202607"
  STORE_LP_202609_FROM = "stores_lp_202609"

  skip_before_action :authenticate_user!, only: %i[show show_202607 return_202607 show_202609 return_202609]
  before_action :enable_gtm, only: %i[show show_202607 show_202609]

  layout "store_lp_202607", only: %i[show_202607]

  def show
    return_query = sanitized_utm_params
    ref = sanitized_store_lp_202607_ref
    return_query[:ref] = ref if ref.present?
    @store_lp_faq_path = stores_faq_path(return_to: stores_lp_path(return_query))

    set_store_lp_meta_tags
  end

  def show_202607
    preserve_attribution = consume_store_lp_202607_attribution_preservation
    persist_store_lp_202607_attribution(preserve: preserve_attribution)
    persist_store_lp_202607_ref(preserve: preserve_attribution)
    resolve_lp_analytics_visit(
      lp_identifier: STORE_LP_202607_FROM,
      preserve_existing_traffic: preserve_attribution
    )

    @store_lp_202607_contact_params = tracking_query_params(from: STORE_LP_202607_FROM)
    @store_lp_202607_registration_params = @store_lp_202607_contact_params.dup
    store_lp_202607_registration_ref = sanitized_store_lp_202607_ref || store_lp_202607_ref
    @store_lp_202607_registration_params[:ref] = store_lp_202607_registration_ref if store_lp_202607_registration_ref.present?

    set_store_lp_202607_meta_tags
  end

  def return_202607
    preserve_store_lp_202607_attribution_once!

    query = {}
    query[:ref] = store_lp_202607_ref if store_lp_202607_ref.present?

    redirect_to stores_lp_202607_path(query)
  end

  def show_202609
    preserve_attribution = consume_store_lp_202609_attribution_preservation
    persist_store_lp_202609_attribution(preserve: preserve_attribution)
    persist_store_lp_202609_ref(preserve: preserve_attribution)
    resolve_lp_analytics_visit(
      lp_identifier: STORE_LP_202609_FROM,
      preserve_existing_traffic: preserve_attribution
    )

    @store_lp_202609_contact_params = tracking_query_params(from: STORE_LP_202609_FROM)
    @store_lp_202609_registration_params = @store_lp_202609_contact_params.dup
    registration_ref = sanitized_store_lp_202609_ref || store_lp_202609_ref
    @store_lp_202609_registration_params[:ref] = registration_ref if registration_ref.present?

    return_query = sanitized_utm_params
    return_query[:ref] = registration_ref if registration_ref.present?
    return_path = stores_lp_202609_path(return_query)
    @store_lp_202609_faq_path = stores_faq_path(return_to: return_path)

    set_store_lp_202609_meta_tags
    render layout: "store_lp_202609"
  end

  def return_202609
    preserve_store_lp_202609_attribution_once!

    query = {}
    query[:ref] = store_lp_202609_ref if store_lp_202609_ref.present?

    redirect_to stores_lp_202609_path(query)
  end

  private

  def resolve_lp_analytics_visit(lp_identifier:, preserve_existing_traffic:)
    visit = LpAnalytics::Visits::ResolveService.new(
      public_id: lp_analytics_visit_public_id,
      lp_identifier: lp_identifier,
      traffic_attributes: {
        traffic_source: params[:from],
        utm_source: params[:utm_source],
        utm_medium: params[:utm_medium],
        utm_campaign: params[:utm_campaign],
        utm_content: params[:utm_content],
        referral_code: params[:ref]
      },
      user_agent: request.user_agent,
      preserve_existing_traffic: preserve_existing_traffic
    ).call

    remember_lp_analytics_visit!(visit.public_id)
    @lp_analytics_visit_public_id = visit.public_id
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("[lp_analytics] visit resolution failed error=#{error.class.name}")
    session.delete(LP_ANALYTICS_VISIT_PUBLIC_ID_SESSION_KEY)
    @lp_analytics_visit_public_id = nil
  end

  def persist_store_lp_202607_attribution(preserve:)
    attribution = store_lp_202607_attribution_payload(from: STORE_LP_202607_FROM)

    if attribution.present?
      session[STORE_LP_202607_ATTRIBUTION_SESSION_KEY] = attribution
    elsif !preserve
      delete_store_lp_202607_attribution
    end
  end

  def persist_store_lp_202607_ref(preserve:)
    ref = sanitized_store_lp_202607_ref

    if ref.present?
      session[STORE_LP_202607_REF_SESSION_KEY] = ref
    elsif !preserve
      delete_store_lp_202607_ref
    end
  end

  def persist_store_lp_202609_attribution(preserve:)
    attribution = store_lp_202609_attribution_payload(from: STORE_LP_202609_FROM)

    if attribution.present?
      session[STORE_LP_202609_ATTRIBUTION_SESSION_KEY] = attribution
    elsif !preserve
      delete_store_lp_202609_attribution
    end
  end

  def persist_store_lp_202609_ref(preserve:)
    ref = sanitized_store_lp_202609_ref

    if ref.present?
      session[STORE_LP_202609_REF_SESSION_KEY] = ref
    elsif !preserve
      delete_store_lp_202609_ref
    end
  end

  def set_store_lp_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    title = "店舗向けライブ配信LP"
    description = "#{brand_name}は、夜の店が既存客向けにライブ配信を行い、ドリンク送信と消化で売上をつくる店舗向けサービスです。"

    set_meta_tags(
      title: title,
      description: description,
      noindex: false,
      nofollow: false,
      canonical: stores_lp_url,
      og: {
        title: "#{title} | #{brand_name}",
        description: description,
        type: "website",
        url: stores_lp_url,
        image: view_context.image_url("logo.png")
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end

  def set_store_lp_202607_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    title = "夜のお店のための新しい遠隔配信ツール"
    description = "#{brand_name}は、夜のお店が既存客向けに遠隔配信を行い、ドリンク送信と消化で売上をつくる店舗向けサービスです。"

    set_meta_tags(
      title: title,
      description: description,
      noindex: true,
      nofollow: false,
      canonical: stores_lp_202607_url,
      og: {
        title: "#{title} | #{brand_name}",
        description: description,
        type: "website",
        url: stores_lp_202607_url,
        image: view_context.image_url("store_lp_202607/logo/01.png")
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end

  def set_store_lp_202609_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    title = "来店できない時間を店舗売上の機会に"
    description = "#{brand_name}は、来店できない日にもキャストとお客様をつなぎ、消化されたギフトを店舗売上として管理できる夜のお店向けライブ配信サービスです。"

    set_meta_tags(
      title: title,
      description: description,
      noindex: true,
      nofollow: false,
      canonical: stores_lp_202609_url,
      og: {
        title: "#{title} | #{brand_name}",
        description: description,
        type: "website",
        url: stores_lp_202609_url,
        image: view_context.image_url("store_lp_202607/logo/01.png")
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end
end
