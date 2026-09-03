require "test_helper"
require_relative "../support/image_upload_verification_helpers"

class SystemAdminImageUploadVerificationRunsTest < ActionDispatch::IntegrationTest
  include ImageUploadVerificationHelpers

  setup do
    @admin = User.create!(email: "upload-runs-admin@example.com", password: "password", role: :system_admin)
    @base = system_admin_image_upload_verification_runs_path
  end

  teardown do
    ImageUploadVerificationRun.where(user: @admin).update_all(cleanup_after: 1.hour.ago)
    ImageUploadVerifications::CleanupService.new.call
    close_verification_files
  end

  test "all write endpoints enforce login roles and feature flag" do
    endpoints = [ [ :post, @base ], [ :post, "#{@base}/1/multipart" ], [ :post, "#{@base}/1/complete" ],
      [ :post, "#{@base}/1/direct_upload/source" ], [ :delete, "#{@base}/1" ] ]
    assert_no_difference([ "ImageUploadVerificationRun.count", "ActiveStorage::Blob.count" ]) do
      with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => "1") do
        endpoints.each do |method, path|
          public_send(method, path)
          assert_redirected_to new_user_session_path
        end
        %i[customer cast store_admin].each do |role|
          user = User.create!(email: "upload-runs-#{role}@example.com", password: "password", role: role)
          sign_in user
          endpoints.each do |method, path|
            public_send(method, path)
            assert_response :forbidden
          end
          sign_out :user
        end
      end
      with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => nil) do
        sign_in @admin
        endpoints.each do |method, path|
          public_send(method, path)
          assert_response :not_found
        end
      end
    end
  end

  test "multipart and actual Disk direct PUT both return validated reports without changing production attachments" do
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => "1") do
      sign_in @admin
      assert_no_difference("ActiveStorage::Attachment.count") do
        [ "multipart", "direct" ].each do |transport|
          post @base, params: { verification: { transport: transport, crop_data: crop_data } }, as: :json
          assert_response :created
          id = response.parsed_body.fetch("id")
          upload = jpeg_upload
          if transport == "multipart"
            post "#{@base}/#{id}/multipart", params: { verification: {
              source: Rack::Test::UploadedFile.new(upload.path, "image/jpeg"),
              display: Rack::Test::UploadedFile.new(jpeg_upload.path, "image/jpeg")
            } }
          else
            ids = %w[source display].to_h do |role|
              bytes = File.binread(upload.path)
              post "#{@base}/#{id}/direct_upload/#{role}", params: { blob: { filename: "private-name.jpg", byte_size: bytes.bytesize,
                checksum: Digest::MD5.base64digest(bytes), content_type: "image/jpeg", metadata: { user_id: 999 } } }, as: :json
              assert_response :success
              data = response.parsed_body
              assert_equal "#{role}.jpg", data["filename"]
              url = URI(data.fetch("direct_upload").fetch("url"))
              put url.request_uri, params: bytes, headers: { "CONTENT_TYPE" => "image/jpeg", "CONTENT_LENGTH" => bytes.bytesize.to_s }
              assert_response :no_content
              [ role, data.fetch("signed_id") ]
            end
            post "#{@base}/#{id}/complete", params: { verification: ids }, as: :json
          end
          assert_response :success
          assert_equal "complete", response.parsed_body["state"]
          assert_equal transport, response.parsed_body["transport"]
          assert_equal "no-store", response.headers["Cache-Control"]
          assert_equal 1200, response.parsed_body.dig("images", "source", "width")
          delete "#{@base}/#{id}"
          assert_response :success
          assert_equal "canceled", response.parsed_body["state"]
        end
      end
    end
  end

  test "write routes reject missing CSRF tokens" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => "1") do
      sign_in @admin
      post @base, params: { verification: { transport: "multipart", crop_data: crop_data } }, as: :json
      assert_response :unprocessable_content
    end
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
