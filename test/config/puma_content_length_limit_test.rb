# frozen_string_literal: true

require "test_helper"
require "puma"
require "puma/configuration"

class PumaContentLengthLimitTest < ActiveSupport::TestCase
  test "rejects request bodies above the image pair multipart ceiling" do
    configuration = Puma::Configuration.new(config_files: [ Rails.root.join("config/puma.rb").to_s ])
    configuration.load
    configuration.clamp

    assert_equal ImageAttachments::MultipartLimits::MAX_REQUEST_BYTES,
      configuration.options.fetch(:http_content_length_limit)
  end
end
