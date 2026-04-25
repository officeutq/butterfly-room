class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_default_meta_tags

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def after_sign_in_path_for(resource)
    stored_location = stored_location_for(resource)

    auto_set_current_store_and_booth_on_sign_in(resource)
    stored_location || super
  end

  private

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
    set_meta_tags(
      site: "Butterflyve",
      title: "Butterflyve",
      description: "Butterflyveは、視聴者・キャスト・店舗をつなぐライブ配信サービスです。",
      reverse: true,
      separator: "|",
      noindex: true,
      nofollow: true,
      og: {
        site_name: "Butterflyve",
        title: "Butterflyve",
        description: "Butterflyveは、視聴者・キャスト・店舗をつなぐライブ配信サービスです。",
        type: "website",
        image: view_context.image_url("logo.png")
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end
end
