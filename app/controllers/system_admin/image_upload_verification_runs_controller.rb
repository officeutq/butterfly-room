# frozen_string_literal: true

module SystemAdmin
  class ImageUploadVerificationRunsController < BaseController
    include ActiveStorage::SetCurrent
    before_action :require_verification_enabled!
    before_action -> { response.headers["Cache-Control"] = "no-store" }

    rescue_from ImageUploadVerifications::ImageValidator::Invalid, with: :invalid
    rescue_from ImageUploadVerifications::UploadService::Conflict, with: :conflict
    rescue_from ImageUploadVerifications::UploadService::CapacityExceeded, with: :capacity_exceeded
    rescue_from ImageUploadVerifications::UploadService::StorageError, with: :storage_error

    def create
      payload = params.expect(verification: [ :transport, crop_data: {} ])
      run = service.create(transport: payload[:transport], crop_data: payload[:crop_data]&.to_h)
      render json: { id: run.id, expires_at: run.expires_at.iso8601, cleanup_after: run.cleanup_after.iso8601 }, status: :created
    end

    def direct_upload
      attributes = params.expect(blob: [ :byte_size, :checksum, :content_type ]).to_h
      render json: service.direct_upload(id: params[:id], role: params[:role], attributes: attributes)
    end

    def multipart
      uploads = params.expect(verification: [ :source, :display ]).to_h
      render json: service.multipart(id: params[:id], uploads: uploads)
    end

    def complete
      signed_ids = params.expect(verification: [ :source, :display ]).to_h
      render json: service.complete(id: params[:id], signed_ids: signed_ids)
    end

    def destroy
      render json: service.cancel(id: params[:id])
    end

    private

    def service
      @service ||= ImageUploadVerifications::UploadService.new(user: current_user)
    end

    def require_verification_enabled!
      head :not_found unless image_upload_verification_enabled?
    end

    def invalid(error)
      render json: { error: error.message }, status: :unprocessable_content
    end

    def conflict(error)
      render json: { error: error.message }, status: :conflict
    end

    def capacity_exceeded(error)
      render json: { error: error.message }, status: :too_many_requests
    end

    def storage_error(error)
      render json: { error: error.message }, status: :bad_gateway
    end
  end
end
