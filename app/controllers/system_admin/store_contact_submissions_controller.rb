# frozen_string_literal: true

module SystemAdmin
  class StoreContactSubmissionsController < SystemAdmin::BaseController
    before_action :set_store_contact_submission, only: %i[show resend_admin_notification]

    def index
      @store_contact_submissions =
        StoreContactSubmission.order(created_at: :desc, id: :desc)
      @admin_notification_email = StoreContactSubmissionMailer.admin_email
    end

    def show
    end

    def resend_admin_notification
      StoreContactSubmissions::ResendAdminNotificationService.new(
        store_contact_submission: @store_contact_submission
      ).call

      redirect_to system_admin_store_contact_submissions_path,
        notice: "管理者宛メールの再送を受け付けました"
    rescue StoreContactSubmissions::ResendAdminNotificationService::AdminEmailNotConfiguredError
      redirect_to system_admin_store_contact_submissions_path,
        alert: "管理者メールアドレスが設定されていないため、再送できません"
    end

    private

    def set_store_contact_submission
      @store_contact_submission = StoreContactSubmission.find(params[:id])
    end
  end
end
