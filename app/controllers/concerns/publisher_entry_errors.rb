module PublisherEntryErrors
  extend ActiveSupport::Concern

  included do
    rescue_from StreamSessions::PublisherControl::Error, with: :render_publisher_entry_error
  end

  private

  def render_publisher_entry_error(error)
    respond_to do |format|
      format.json { render json: { error: error.code, message: error.message }, status: error.status }
      format.any do
        @publisher_entry_error = error
        render "cast/booths/publisher_entry_error", formats: [ :html ], status: error.status
      end
    end
  end
end
