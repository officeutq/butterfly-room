module Admin
  class BaseController < ApplicationController
    before_action -> { require_at_least!(:store_admin) }
    after_action :store_admin_return_to
    helper_method :store_information_return_options

    private

    def store_information_return_options(store = current_store)
      return {} unless params[:return_to] == "store_information"

      { selection_store_id: store.id, return_to: "store_information" }
    end

    # admin領域の「直前ページ」をsessionに保存（Issue #270）
    #
    # - GET の HTML のみ対象（操作POST等は除外）
    # - 200 OK のときだけ保存（リダイレクト/エラーは「直前ページ」にしない）
    # - /admin/stores（選択画面）と /admin/current_store（選択POST）では保存しない
    # - 保存値は /admin/ で始まる相対パスのみ（安全側）
    def store_admin_return_to
      return unless request.get? || request.head?
      return unless request.format.html?
      return unless response.status == 200
      return unless request.fullpath.start_with?("/admin/")

      # 選択画面 / 選択POST では保存しない
      return if request.path == "/admin/stores"
      return if request.path == "/admin/current_store"
      return if turbo_frame_request?

      fullpath = request.fullpath.to_s

      # open redirect / 不正URL対策：/admin/ で始まり、// を含まないものだけ
      return unless fullpath.start_with?("/admin/")
      return if fullpath.start_with?("//")
      return if fullpath.include?("\n") || fullpath.include?("\r")
      return if fullpath.include?("\0")

      session[:admin_return_to] = fullpath
    end

    helper_method :current_store


    def admin_membership_exists_for_store?(store_id)
      StoreMembership.exists?(
        user_id: current_user.id,
        store_id: store_id,
        membership_role: StoreMembership.membership_roles[:admin]
      )
    end
  end
end
