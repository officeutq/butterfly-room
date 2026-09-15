# frozen_string_literal: true

module Admin
  class CurrentStoresController < Admin::BaseController
    def create
      result = resolve_current_selection(purpose: :select_store, target_id: params.require(:store_id))
      unless result.success?
        return render_selection_problem(selection_error_message(result))
      end

      destination = prepare_selection_destination(kind: :store, result: result)
      expected_booth_id = result.booth&.id
      result = resolve_current_selection(purpose: :select_store, target_id: result.store.id)
      return render_selection_problem(selection_error_message(result)) unless result.success?
      if result.booth&.id != expected_booth_id
        return render_selection_problem("ブースの状態が更新されています。選択し直してください")
      end
      save_current_selection(result)
      respond_selection_success(destination, notice: "店舗を切り替えました")
    rescue ActionController::ParameterMissing
      render_selection_problem("店舗を選択してください")
    rescue ::Booths::EnterAsCastService::NotAuthorized
      render_selection_problem("選択できないブースです", status: :forbidden)
    end
  end
end
