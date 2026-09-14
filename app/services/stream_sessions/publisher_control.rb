module StreamSessions
  module PublisherControl
    class Error < StandardError
      attr_reader :code, :status, :booth, :details

      def initialize(code:, message:, booth:, status: :conflict, details: {})
        super(message)
        @code = code
        @status = status
        @booth = booth
        @details = details
      end
    end

    def self.enabled?
      ENV.fetch("ACTUAL_PUBLISHER_CONTROL_ENABLED", "false") == "true"
    end

    # 開始要求が認証時のUserインスタンスを保持していても、退会の確定後は許可しない。
    def self.active_actor?(actor)
      actor.present? && User.uncached { User.active.where(id: actor.id).exists? }
    end

    def self.valid_request_id?(value)
      value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    def self.generation(value)
      return unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))

      number = value.to_i
      number if number.between?(0, 9_223_372_036_854_775_806)
    end
  end
end
