# frozen_string_literal: true

module Admin
  class CurrentStoresController < Admin::BaseController
    def create
      result = resolve_current_selection(purpose: :select_store, target_id: params.require(:store_id))
      unless save_current_selection(result)
        return render_selection_problem(selection_error_message(result))
      end

      respond_selection_success(selection_return_path(kind: :store, result: result), notice: "店舗を切り替えました")
    rescue ActionController::ParameterMissing
      render_selection_problem("店舗を選択してください")
    end
  end
end
