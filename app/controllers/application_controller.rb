class ApplicationController < ActionController::Base
  GTM_CONTAINER_ID = "GTM-KNT7H4CG"
  STORE_LP_202607_ATTRIBUTION_SESSION_KEY = :store_lp_202607_attribution
  STORE_LP_202607_REF_SESSION_KEY = :store_lp_202607_ref
  PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY = :preserve_store_lp_202607_attribution_once
  STORE_LP_202607_FROM = "stores_lp_202607"
  STORE_LP_202609_ATTRIBUTION_SESSION_KEY = :store_lp_202609_attribution
  STORE_LP_202609_REF_SESSION_KEY = :store_lp_202609_ref
  PRESERVE_STORE_LP_202609_ATTRIBUTION_ONCE_SESSION_KEY = :preserve_store_lp_202609_attribution_once
  STORE_LP_202609_FROM = "stores_lp_202609"
  LP_ANALYTICS_VISIT_PUBLIC_ID_SESSION_KEY = :lp_analytics_visit_public_id
  LP_ANALYTICS_VISIT_PUBLIC_IDS_SESSION_KEY = :lp_analytics_visit_public_ids
  LP_ANALYTICS_MAX_SESSION_VISITS = 10
  UTM_PARAM_KEYS = %i[utm_source utm_medium utm_campaign utm_content].freeze
  UTM_PARAM_MAX_LENGTH = 100
  STORE_LP_202607_REF_MAX_LENGTH = 100

  before_action :authenticate_user!
  before_action :set_default_meta_tags

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern,
                unless: -> { controller_path == "booths" && action_name.in?(%w[share share_ogp_image]) }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def after_sign_in_path_for(resource)
    stored_location = stored_location_for(resource)

    auto_set_current_store_and_booth_on_sign_in(resource)
    stored_location || super
  end

  helper_method :gtm_enabled?,
                :gtm_container_id,
                :staging_environment?,
                :image_upload_verification_enabled?

  private

  def enable_gtm
    @gtm_enabled = true
  end

  def gtm_enabled?
    @gtm_enabled == true && Staging::Runtime.gtm_enabled?
  end

  def gtm_container_id
    ENV["GTM_CONTAINER_ID"].presence || GTM_CONTAINER_ID
  end

  def staging_environment?
    Staging::Runtime.staging?
  end

  def image_upload_verification_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["IMAGE_UPLOAD_VERIFICATION_ENABLED"])
  end

  def sanitized_utm_params(source = params)
    UTM_PARAM_KEYS.each_with_object({}) do |key, sanitized|
      raw_value = source[key] if source.respond_to?(:[])
      raw_value = source[key.to_s] if raw_value.blank? && source.respond_to?(:[])
      next unless raw_value.is_a?(String)

      value = raw_value.strip
      next if value.blank?

      sanitized[key] = value[0, UTM_PARAM_MAX_LENGTH]
    end
  end

  def sanitized_store_lp_202607_ref(source = params)
    return nil unless source.respond_to?(:[])

    raw_value = source[:ref]
    raw_value = source["ref"] if raw_value.blank?
    return nil unless raw_value.is_a?(String)

    value = raw_value.strip
    return nil if value.blank?

    value[0, STORE_LP_202607_REF_MAX_LENGTH]
  end

  def sanitized_store_lp_202609_ref(source = params)
    sanitized_store_lp_202607_ref(source)
  end

  def tracking_query_params(from: nil, utm_params: {})
    query = {}
    query[:from] = from if from.present?
    query.merge!(sanitized_utm_params(utm_params))
    query
  end

  def tracking_session_payload(from: nil, utm_params: {})
    tracking_query_params(from:, utm_params:).transform_keys(&:to_s)
  end

  def store_lp_202607_attribution
    session[STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
  end

  def store_lp_202607_ref
    session[STORE_LP_202607_REF_SESSION_KEY]
  end

  def store_lp_202609_attribution
    session[STORE_LP_202609_ATTRIBUTION_SESSION_KEY]
  end

  def store_lp_202609_ref
    session[STORE_LP_202609_REF_SESSION_KEY]
  end

  def lp_analytics_visit_public_id
    session[LP_ANALYTICS_VISIT_PUBLIC_ID_SESSION_KEY]
  end

  def remember_lp_analytics_visit!(public_id)
    normalized_public_id = public_id.to_s.strip
    return unless LpAnalytics::Visit::UUID_PATTERN.match?(normalized_public_id)

    public_ids = lp_analytics_authorized_visit_public_ids
    public_ids.delete(normalized_public_id)
    public_ids << normalized_public_id

    session[LP_ANALYTICS_VISIT_PUBLIC_ID_SESSION_KEY] = normalized_public_id
    session[LP_ANALYTICS_VISIT_PUBLIC_IDS_SESSION_KEY] = public_ids.last(LP_ANALYTICS_MAX_SESSION_VISITS)
  end

  def lp_analytics_authorized_visit_public_ids
    current_public_id = lp_analytics_visit_public_id
    remembered_public_ids = Array(session[LP_ANALYTICS_VISIT_PUBLIC_IDS_SESSION_KEY])

    ([ current_public_id ] + remembered_public_ids).filter_map do |public_id|
      normalized_public_id = public_id.to_s.strip
      normalized_public_id if LpAnalytics::Visit::UUID_PATTERN.match?(normalized_public_id)
    end.uniq
  end

  def authorized_lp_analytics_completion_visit(lp_identifier:)
    public_id =
      if params.key?(:lp_analytics_visit_id)
        params[:lp_analytics_visit_id].to_s.strip
      else
        lp_analytics_visit_public_id
      end
    return unless lp_analytics_authorized_visit_public_ids.include?(public_id)

    visit = LpAnalytics::Visit.find_by_public_id(public_id)
    visit if visit&.lp_identifier == lp_identifier
  end

  def lp_analytics_authorized_visit_available?(lp_identifier:)
    return false unless LpAnalytics::Configuration.supported_lp?(lp_identifier)

    LpAnalytics::Visit.where(
      public_id: lp_analytics_authorized_visit_public_ids,
      lp_identifier: lp_identifier
    ).exists?
  end

  def store_lp_202607_attribution_payload(from: STORE_LP_202607_FROM, source: params)
    utm_params = sanitized_utm_params(source)
    return nil if utm_params.blank?

    tracking_session_payload(from:, utm_params:)
  end

  def store_lp_202609_attribution_payload(from: STORE_LP_202609_FROM, source: params)
    utm_params = sanitized_utm_params(source)
    return nil if utm_params.blank?

    tracking_session_payload(from:, utm_params:)
  end

  def completion_tracking_payload(from:)
    payload = tracking_session_payload(from:)
    attribution =
      case payload["from"]
      when STORE_LP_202607_FROM
        store_lp_202607_attribution
      when STORE_LP_202609_FROM
        store_lp_202609_attribution
      end
    attribution_from = attribution_from(attribution)
    source_from = payload["from"].presence || attribution_from

    if [ STORE_LP_202607_FROM, STORE_LP_202609_FROM ].include?(source_from)
      utm_params = sanitized_utm_params(attribution)
      payload["utm"] = utm_params.transform_keys(&:to_s) if utm_params.present?
    end

    payload
  end

  def gtm_conversion_event_payload(event:, completion:)
    payload = { event: event }
    from = completion_from(completion)
    payload[:from] = from if from.present?

    sanitized_utm_params(completion_utm(completion)).each do |key, value|
      payload[key] = value
    end

    payload
  end

  def delete_store_lp_202607_attribution
    session.delete(STORE_LP_202607_ATTRIBUTION_SESSION_KEY)
  end

  def delete_store_lp_202607_ref
    session.delete(STORE_LP_202607_REF_SESSION_KEY)
  end

  def delete_store_lp_202609_attribution
    session.delete(STORE_LP_202609_ATTRIBUTION_SESSION_KEY)
  end

  def delete_store_lp_202609_ref
    session.delete(STORE_LP_202609_REF_SESSION_KEY)
  end

  def preserve_store_lp_202607_attribution_once!
    session[PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY] = true
  end

  def consume_store_lp_202607_attribution_preservation
    # Turbo may fetch the LP before a tracked-asset full reload; keep the flag for the document request.
    return true if session[PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY] == true && turbo_drive_request?

    session.delete(PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY) == true
  end

  def preserve_store_lp_202609_attribution_once!
    session[PRESERVE_STORE_LP_202609_ATTRIBUTION_ONCE_SESSION_KEY] = true
  end

  def consume_store_lp_202609_attribution_preservation
    # Turbo may fetch the LP before a tracked-asset full reload; keep the flag for the document request.
    return true if session[PRESERVE_STORE_LP_202609_ATTRIBUTION_ONCE_SESSION_KEY] == true && turbo_drive_request?

    session.delete(PRESERVE_STORE_LP_202609_ATTRIBUTION_ONCE_SESSION_KEY) == true
  end

  def turbo_drive_request?
    request.headers["X-Turbo-Request-ID"].present?
  end

  def attribution_from(attribution)
    return nil if attribution.blank?

    attribution[:from].presence || attribution["from"].presence
  end

  def completion_from(completion)
    return nil if completion.blank?

    completion[:from].presence || completion["from"].presence
  end

  def completion_utm(completion)
    return {} if completion.blank?

    completion[:utm] || completion["utm"] || {}
  end

  # 既存：完全一致（そのまま残す。階層が必要な箇所は require_at_least! を使う）
  def require_role!(*roles)
    authenticate_user! # Devise

    role = current_user.role.to_sym
    return if roles.include?(role)

    head :forbidden
  end

  def require_at_least!(required_role)
    authenticate_user! # Devise

    return if current_user.at_least?(required_role)

    head :forbidden
  end

  def clear_guest_unauthenticated_alert
    return if user_signed_in?
    return unless flash[:alert] == I18n.t("devise.failure.unauthenticated")

    flash.delete(:alert)
  end

  def authorize!(policy_class, record, action)
    policy = policy_class.new(current_user, record)
    head(:forbidden) unless policy.public_send("#{action}?")
  end

  def auto_set_current_store_and_booth_on_sign_in(user)
    return if user.blank?

    selectable_stores = selectable_stores_for_auto_current(user)
    if selectable_stores.size == 1
      session[:current_store_id] = selectable_stores.first.id
    end

    selectable_booths = selectable_booths_for_auto_current(user)
    if selectable_booths.size == 1
      booth = selectable_booths.first
      session[:current_booth_id] = booth.id
      session[:current_store_id] = booth.store_id
    end
  end

  def selectable_stores_for_auto_current(user)
    if user.system_admin?
      Store.order(:id).to_a
    elsif user.at_least?(:store_admin)
      Store
        .joins(:store_memberships)
        .where(store_memberships: {
          user_id: user.id,
          membership_role: StoreMembership.membership_roles[:admin]
        })
        .distinct
        .order(:id)
        .to_a
    else
      []
    end
  end

  def selectable_booths_for_auto_current(user)
    booths =
      if user.system_admin?
        Booth.all
      elsif user.at_least?(:store_admin)
        Booth.joins(store: :store_memberships)
             .where(store_memberships: { user_id: user.id, membership_role: :admin })
             .distinct
      elsif user.at_least?(:cast)
        Booth.joins(:booth_casts)
             .where(booth_casts: { cast_user_id: user.id })
             .distinct
      else
        Booth.none
      end

    booths.active
          .order(Arel.sql('"booths"."archived_at" ASC NULLS FIRST'), id: :desc)
          .to_a
  end

  def set_default_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    description = "Butterflyve（バタフライブ）は、視聴者・キャスト・店舗をつなぐライブ配信サービスです。"

    set_meta_tags(
      site: brand_name,
      title: "Butterflyve",
      description: description,
      reverse: true,
      separator: "|",
      noindex: true,
      nofollow: true,
      og: {
        site_name: brand_name,
        title: brand_name,
        description: description,
        type: "website",
        image: view_context.image_url("logo.png")
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end
end
