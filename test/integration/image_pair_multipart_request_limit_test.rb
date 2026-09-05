# frozen_string_literal: true

require "test_helper"

class ImagePairMultipartRequestLimitTest < ActionDispatch::IntegrationTest
  test "returns the retryable 413 contract before routing an oversized multipart request" do
    post "/not-a-route",
      params: "small body",
      headers: {
        "CONTENT_TYPE" => "multipart/form-data; boundary=test-boundary",
        "CONTENT_LENGTH" => (ImageAttachments::MultipartLimits::MAX_REQUEST_BYTES + 1).to_s
      }

    assert_response :content_too_large
    assert_equal "image_pair_request_too_large", response.parsed_body.fetch("error")
    assert_equal true, response.parsed_body.fetch("retryable")
  end

  test "does not apply the Rails multipart guard to an unrelated content type" do
    post "/not-a-route",
      params: "{}",
      headers: {
        "CONTENT_TYPE" => "application/json",
        "CONTENT_LENGTH" => (ImageAttachments::MultipartLimits::MAX_REQUEST_BYTES + 1).to_s
      }

    assert_response :not_found
  end
end
