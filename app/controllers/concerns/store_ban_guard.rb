# frozen_string_literal: true

module StoreBanGuard
  extend ActiveSupport::Concern

  private

  def reject_banned_customer!(store:)
    return if store.blank?
    return unless user_signed_in?
    return unless current_user.customer?

    if Authorization::StoreBanChecker.new(store: store, user: current_user).banned?
      render_banned!
    end
  end

  def render_banned!
    respond_to do |format|
      format.json do
        render json: { error: "banned" }, status: :forbidden
      end

      format.turbo_stream do
        html = <<~HTML
          <turbo-stream action="append" target="comments">
            <template>
              <script>
                window.location.href = #{root_path.to_json};
              </script>
            </template>
          </turbo-stream>
        HTML

        render plain: html, content_type: "text/vnd.turbo-stream.html", status: :ok
      end

      format.html do
        redirect_to root_path, status: :see_other
      end

      format.any { head :forbidden }
    end
  end
end
