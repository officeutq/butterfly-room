# frozen_string_literal: true

module CurrentSelection
  extend ActiveSupport::Concern

  private

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
