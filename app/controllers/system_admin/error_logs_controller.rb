# frozen_string_literal: true

module SystemAdmin
  class ErrorLogsController < LogsController
    private

    def log_kind
      :errors
    end
  end
end
