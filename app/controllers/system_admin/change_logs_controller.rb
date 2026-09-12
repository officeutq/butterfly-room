# frozen_string_literal: true

module SystemAdmin
  class ChangeLogsController < LogsController
    private

    def log_kind
      :changes
    end
  end
end
