# frozen_string_literal: true

module StoreContactSubmissions
  class CreateService
    Result = Struct.new(:store_contact_submission, keyword_init: true)

    def initialize(attributes:)
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      store_contact_submission = StoreContactSubmission.new(
        @attributes.merge(source: StoreContactSubmission::SOURCE_STORES_LP)
      )
      store_contact_submission.save!

      Result.new(store_contact_submission: store_contact_submission)
    end
  end
end
