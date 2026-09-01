# frozen_string_literal: true

module SystemAdmin
  class ImageUploadVerificationsController < BaseController
    before_action :require_image_upload_verification_enabled!

    def show
      set_meta_tags(
        title: "画像アップロード検証",
        noindex: true,
        nofollow: true
      )
    end

    private

    def require_image_upload_verification_enabled!
      head :not_found unless image_upload_verification_enabled?
    end
  end
end
