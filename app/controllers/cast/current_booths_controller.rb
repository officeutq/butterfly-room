# frozen_string_literal: true

module Cast
  class CurrentBoothsController < Cast::BaseController
    def create
      result = resolve_current_selection(purpose: :select_booth, target_id: params.require(:booth_id))
      return render_selection_problem(selection_error_message(result)) unless result.success?

      destination = prepare_selection_destination(kind: :booth, result: result)
      result = resolve_current_selection(purpose: :select_booth, target_id: result.booth.id)
      return render_selection_problem(selection_error_message(result)) unless result.success?
      save_current_selection(result)
      respond_selection_success(destination, notice: "ブースを選択しました")
    rescue ActionController::ParameterMissing
      render_selection_problem("ブースを選択してください")
    rescue ::Booths::EnterAsCastService::NotAuthorized
      render_selection_problem("選択できないブースです", status: :forbidden)
    end
  end
end
