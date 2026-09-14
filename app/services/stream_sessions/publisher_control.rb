module StreamSessions
  module PublisherControl
    class Error < StandardError
      attr_reader :code, :status, :booth

      def initialize(code:, message:, booth:, status: :conflict)
        super(message)
        @code = code
        @status = status
        @booth = booth
      end
    end

    def self.enabled?
      ENV.fetch("ACTUAL_PUBLISHER_CONTROL_ENABLED", "false") == "true"
    end
  end
end
