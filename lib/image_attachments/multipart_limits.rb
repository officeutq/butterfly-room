# frozen_string_literal: true

module ImageAttachments
  module MultipartLimits
    MAX_REQUEST_BYTES = 26 * 1024 * 1024
    CLIENT_TIMEOUT_MILLISECONDS = 45_000
  end
end
