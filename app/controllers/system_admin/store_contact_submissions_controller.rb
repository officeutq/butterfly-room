# frozen_string_literal: true

module SystemAdmin
  class StoreContactSubmissionsController < SystemAdmin::BaseController
    before_action :set_store_contact_submission, only: %i[show]

    def index
      @store_contact_submissions =
        StoreContactSubmission.order(created_at: :desc, id: :desc)
    end

    def show
    end

    private

    def set_store_contact_submission
      @store_contact_submission = StoreContactSubmission.find(params[:id])
    end
  end
end
