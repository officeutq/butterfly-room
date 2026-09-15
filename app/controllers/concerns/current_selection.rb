# frozen_string_literal: true

module CurrentSelection
  extend ActiveSupport::Concern

  private

  def current_selection
    @current_selection ||= normalize_current_selection
  end

  def normalize_current_selection
    result = resolve_current_selection
    @selection_was_unset = result.booths.none? { |booth| booth.id.to_s == session[:current_booth_id].to_s }
    save_current_selection(result)
    @current_selection = result
  end

  def current_booth
    current_selection.booth if current_selection.success?
  end

  def current_store
    current_selection.store if current_selection.success?
  end

  def selection_error_message(result = current_selection)
    case result.error
    when :broadcast_fixed
      "配信を終了してから切り替えてください"
    when :broadcast_inconsistent
      "配信状態を確認できません。時間をおいて再度確認してください"
    else
      "選択できない対象です"
    end
  end

  def require_current_booth!(return_to_key: nil, allow_selection: false)
    result = resolve_current_selection(purpose: :require_booth)
    return render_selection_problem(selection_error_message(result), status: :service_unavailable) unless save_current_selection(result)
    return true if result.booth

    if result.booths.empty?
      render_selection_problem("操作可能なブースがありません")
    elsif !request.get? && !request.head? && !allow_selection
      render_selection_problem("対象のブースをヘッダーから選択してください")
    else
      redirect_to select_modal_cast_booths_path(return_to: request.fullpath, return_to_key: return_to_key, required: 1)
      false
    end
  end

  def require_current_store!
    result = resolve_current_selection(purpose: :require_store)
    return render_selection_problem(selection_error_message(result), status: :service_unavailable) unless save_current_selection(result)
    return true if result.store

    if result.stores.empty?
      render_selection_problem("管理可能な店舗がありません")
    elsif !request.get? && !request.head?
      render_selection_problem("対象の店舗をヘッダーから選択してください")
    else
      redirect_to select_modal_admin_stores_path(return_to: request.fullpath, required: 1)
      false
    end
  end

  # 要求対象は呼び出し元で先に認可する。選択をURLの対象に読み替えない。
  def require_selected_booth!(booth, return_to_key: "booth_show", allow_selection: false)
    return false unless require_current_booth!(return_to_key: return_to_key, allow_selection: allow_selection)
    return true if current_booth.id == booth.id

    if (request.get? || request.head?) && @selection_was_unset
      redirect_to selection_booth_path(return_to_key, current_booth)
      false
    else
      render_selection_problem("対象のブースをヘッダーから選択してください")
    end
  end

  def require_selected_store!(store)
    return false unless require_current_store!
    return true if current_store.id == store.id

    render_selection_problem("対象の店舗をヘッダーから選択してください")
  end

  def require_form_store!
    target_id = params[:selection_store_id].to_s
    return render_selection_problem("対象の店舗を確認できません。画面を開き直してください") if target_id.blank?

    store = current_selection.stores.find { |candidate| candidate.id.to_s == target_id }
    return head(:forbidden) unless store

    @selection_form_store = store
    require_selected_store!(store)
  end

  def render_selection_problem(message, status: :conflict)
    @selection_message = message
    respond_to do |format|
      format.json { render json: { error: "selection_mismatch", message: message }, status: status }
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("flash_inner", partial: "shared/flash_message",
          locals: { level: "danger", message: message }), status: status
      end
      format.html do
        if turbo_frame_request?
          flash[:alert] = message
          @redirect_path = dashboard_path
          render "cast/booths/select_modal_redirect", layout: false, status: :ok
        elsif !request.get? && !request.head? && respond_to?(:render_selection_conflict_form, true)
          render_selection_conflict_form(message)
        else
          render "shared/selection_problem", status: status
        end
      end
      format.any { render plain: message, status: status }
    end
    false
  end

  def selection_booth_path(key, booth)
    return dashboard_path unless booth

    case key.to_s
    when "booth_edit"
      booth.archived? ? cast_booth_path(booth) : edit_cast_booth_path(booth)
    when "booth_live"
      booth.archived? ? cast_booth_path(booth) : live_cast_booth_path(booth)
    when "booth_stream_sessions"
      cast_booth_stream_sessions_path(booth)
    else
      cast_booth_path(booth)
    end
  end

  # 戻り先の画面種別を保持し、管理画面の対象IDだけ確定した選択に揃える。
  def selection_return_path(kind:, result: current_selection)
    key = params[:return_to_key].to_s
    return selection_booth_path(key, result.booth) if key.start_with?("booth_")
    return new_admin_cast_invitation_path if key == "cast_invitation"
    return edit_admin_payout_account_path if key == "payout_account_edit"
    return result.store ? edit_admin_store_path(result.store) : dashboard_path if key == "store_edit"

    path = safe_selection_return_to(params[:return_to])
    if path.nil? && [ cast_booths_url, admin_stores_url ].include?(request.referer)
      return dashboard_path
    end
    path ||= safe_selection_return_to(session[kind == :booth ? :cast_return_to : :admin_return_to])
    return dashboard_path unless path

    route = Rails.application.routes.recognize_path(path.split("?").first, method: :get)
    if route[:controller] == "cast/booths" && %w[show edit live].include?(route[:action])
      selection_booth_path("booth_#{route[:action]}", result.booth)
    elsif route[:controller] == "cast/booths/stream_sessions" && route[:action] == "index"
      selection_booth_path("booth_stream_sessions", result.booth)
    elsif route[:controller] == "admin/stores" && route[:action] == "edit"
      result.store ? edit_admin_store_path(result.store) : dashboard_path
    elsif %w[cast/current_booths admin/current_stores].include?(route[:controller]) ||
        (%w[cast/booths admin/stores].include?(route[:controller]) && %w[index select_modal].include?(route[:action]))
      dashboard_path
    else
      path
    end
  rescue ActionController::RoutingError, URI::InvalidURIError, ArgumentError
    dashboard_path
  end

  def safe_selection_return_to(value)
    path = value.to_s
    return unless path.start_with?("/") && !path.start_with?("//")
    return if path.match?(/[\\\x00-\x20]/) || URI::DEFAULT_PARSER.unescape(path).match?(/[\\\x00-\x20]/)

    path
  end

  def resolve_current_selection(purpose: :normalize, target_id: nil, actor: current_user)
    CurrentSelectionService.new(actor: actor,
      current_booth_id: session[:current_booth_id], current_store_id: session[:current_store_id],
      purpose: purpose, target_id: target_id).call
  end

  def save_current_selection(result)
    return false unless result.success?

    result.booth ? session[:current_booth_id] = result.booth.id : session.delete(:current_booth_id)
    result.store ? session[:current_store_id] = result.store.id : session.delete(:current_store_id)
    @current_selection = result
    true
  end
end
