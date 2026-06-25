# frozen_string_literal: true

module SupportInquiries
  class UpdateStatusService
    class NotAllowedError < StandardError; end
    class InvalidStatusError < StandardError; end

    def initialize(actor:, support_inquiry:, status:)
      @actor = actor
      @support_inquiry = support_inquiry
      @status = status.to_s
    end

    def call
      raise NotAllowedError unless @actor&.system_admin?
      raise InvalidStatusError unless SupportInquiry.statuses.key?(@status)

      @support_inquiry.with_lock do
        @support_inquiry.update!(status_attributes)
      end

      @support_inquiry
    end

    private

    def status_attributes
      attributes = { status: @status }
      attributes[:resolved_at] = @status == "resolved" ? Time.current : nil
      attributes
    end
  end
end
