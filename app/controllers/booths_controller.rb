# frozen_string_literal: true

class BoothsController < ApplicationController
  include StoreBanGuard

  layout "share", only: %i[share]

  skip_before_action :authenticate_user!, only: %i[show enter share share_ogp_image]
  before_action :clear_guest_unauthenticated_alert, only: %i[show]
  before_action :redirect_guest_to_welcome, only: %i[enter]
  before_action :set_public_booth, only: %i[show share share_ogp_image viewer_drink_menu]
  before_action :set_entry_booth, only: %i[enter enter_as_cast]
  before_action :reject_banned_customer_for_booth!, only: %i[show viewer_drink_menu]
  before_action :set_viewer_stream_context, only: %i[show viewer_drink_menu]

  def show
    @authenticated_viewer = user_signed_in?

    @wallet =
      if user_signed_in?
        Wallet.find_or_create_by!(customer_user_id: current_user.id) do |w|
          w.available_points = 0
          w.reserved_points = 0
        end
      end

    @comments = load_viewer_comments

    primary_cast = @booth.primary_cast_user

    @booth_favorited =
      user_signed_in? && current_user.favorite_booths.exists?(booth_id: @booth.id)

    @store_favorited =
      user_signed_in? && current_user.favorite_stores.exists?(store_id: @booth.store_id)

    @user_favorited =
      user_signed_in? &&
      primary_cast.present? &&
      current_user.favorite_users.exists?(target_user: primary_cast)
  end

  def share
    @stream_session = resolve_share_stream_session
    @share_url = share_booth_url(@booth, **share_url_options)

    set_share_meta_tags
  end

  def share_ogp_image
    expires_in 1.year, public: true
    send_file Rails.root.join("app/assets/images/booth-share-ogp.jpg"),
              type: "image/jpeg",
              disposition: "inline"
  end

  def viewer_drink_menu
    render partial: "booths/drink_menu",
           locals: {
             booth: @booth,
             stream_session: @stream_session,
             drink_items: @drink_items,
             can_create_drink_order: @can_create_drink_order
           },
           layout: false,
           status: :ok
  end

  def enter
    unless user_signed_in?
      redirect_to welcome_path
      return
    end

    if current_user.customer?
      redirect_to booth_path(@booth)
      return
    end

    if current_user.cast?
      if BoothCast.exists?(cast_user_id: current_user.id, booth_id: @booth.id)
        set_current_context_for_booth!

        result = ::Booths::EnterAsCastService.new(
          booth: @booth,
          actor: current_user
        ).call

        case result.action
        when :redirect_live
          redirect_to live_cast_booth_path(result.booth)
        when :already_live_elsewhere
          redirect_back fallback_location: root_path, alert: "他のブースで配信中のため開始できません"
        when :occupied_by_other
          redirect_back fallback_location: root_path, alert: "このブースはすでに配信中です"
        else
          redirect_back fallback_location: root_path, alert: "配信導線の開始に失敗しました"
        end
      else
        redirect_to booth_path(@booth)
      end
      return
    end

    if current_user.store_admin?
      if current_user.admin_of_store?(@booth.store_id)
        if turbo_frame_request?
          render partial: "booths/enter_modal", locals: { booth: @booth }, layout: false, status: :ok
        else
          render :enter, status: :ok
        end
      else
        redirect_to booth_path(@booth)
      end
      return
    end

    if current_user.system_admin?
      if turbo_frame_request?
        render partial: "booths/enter_modal", locals: { booth: @booth }, layout: false, status: :ok
      else
        render :enter, status: :ok
      end
      return
    end

    redirect_to booth_path(@booth)
  rescue ::Booths::EnterAsCastService::NotAuthorized
    head :forbidden
  end

  def enter_as_cast
    require_at_least!(:cast)

    set_current_context_for_booth!

    result = ::Booths::EnterAsCastService.new(
      booth: @booth,
      actor: current_user
    ).call

    case result.action
    when :redirect_live
      redirect_to live_cast_booth_path(result.booth)
    when :already_live_elsewhere
      redirect_back fallback_location: root_path, alert: "他のブースで配信中のため開始できません"
    when :occupied_by_other
      redirect_back fallback_location: root_path, alert: "このブースはすでに配信中です"
    else
      redirect_back fallback_location: root_path, alert: "配信導線の開始に失敗しました"
    end
  rescue ::Booths::EnterAsCastService::NotAuthorized
    head :forbidden
  end

  private

  def redirect_guest_to_welcome
    redirect_to welcome_path unless user_signed_in?
  end

  def set_public_booth
    @booth = Booth.active.in_published_stores.find(params[:id])
  end

  def resolve_share_stream_session
    stream_id = normalized_share_stream_id
    return if stream_id.blank?

    @booth.stream_sessions.find_by(id: stream_id)
  end

  def normalized_share_stream_id
    value = params[:stream].to_s
    return unless value.match?(/\A\d+\z/)

    stream_id = value.to_i
    return if stream_id.zero? || stream_id > 9_223_372_036_854_775_807

    stream_id
  end

  def share_url_options
    return {} if @stream_session.blank?

    { stream: @stream_session.id }
  end

  def set_share_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    title = @stream_session&.title.presence || @booth.name
    share_user =
      if @stream_session.present?
        @stream_session.started_by_cast_user
      else
        @booth.primary_cast_user
      end
    description = view_context.booth_share_og_description(share_user)
    image =
      if @booth.thumbnail_image.attached?
        url_for(@booth.thumbnail_image.variant(:ogp))
      else
        share_ogp_image_booth_url(@booth, **share_url_options, format: :jpg)
      end

    set_meta_tags(
      title: title,
      description: description,
      noindex: true,
      nofollow: false,
      canonical: @share_url,
      og: {
        site_name: brand_name,
        title: title,
        description: description,
        type: "website",
        url: @share_url,
        image: image
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end

  def set_entry_booth
    @booth = Booth.active.find(params[:id])
    return if @booth.store.published?
    return if user_signed_in? && Authorization::BoothPolicy.new(current_user, @booth).update?

    raise ActiveRecord::RecordNotFound
  end

  def set_viewer_stream_context
    @stream_session = @booth.current_stream_session
    @drink_items = @booth.store.drink_items.with_attached_custom_icon.enabled_only.ordered
    @can_create_drink_order = can_create_drink_order?
  end

  def can_create_drink_order?
    return false unless @stream_session.present? && user_signed_in?

    Authorization::ViewerPolicy.new(current_user, @stream_session).create_drink_order?
  end

  def load_viewer_comments
    return [] unless @stream_session.present?

    Comment.alive.where(stream_session: @stream_session)
           .order(created_at: :desc)
           .limit(50)
           .reverse
  end

  def reject_banned_customer_for_booth!
    reject_banned_customer!(store: @booth.store)
  end

  def set_current_context_for_booth!
    session[:current_booth_id] = @booth.id
    session[:current_store_id] = @booth.store_id
  end
end
