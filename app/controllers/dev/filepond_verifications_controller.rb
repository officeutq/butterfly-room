# frozen_string_literal: true

module Dev
  class FilepondVerificationsController < ApplicationController
    before_action :ensure_development!
    before_action -> { require_at_least!(:system_admin) }

    def show
      @form_upload = FilepondTestUpload.new
      @upload = requested_upload || latest_upload
    end

    def create
      @form_upload = FilepondTestUpload.new(filepond_test_upload_params)

      if @form_upload.save
        redirect_to dev_filepond_verification_path(upload_id: @form_upload.id),
                    notice: "FilePond 検証画像を保存しました"
      else
        @upload = latest_upload
        render :show, status: :unprocessable_entity
      end
    end

    private

    def ensure_development!
      head :not_found unless Rails.env.development?
    end

    def filepond_test_upload_params
      params.require(:filepond_test_upload).permit(:title, :image)
    end

    def requested_upload
      return if params[:upload_id].blank?

      FilepondTestUpload.with_attached_image.find_by(id: params[:upload_id])
    end

    def latest_upload
      FilepondTestUpload.with_attached_image.order(created_at: :desc, id: :desc).first
    end
  end
end
