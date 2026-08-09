# frozen_string_literal: true

module LpAnalytics
  class ClientClassifier
    Result = Data.define(:device_type, :browser_type)
    MAX_USER_AGENT_LENGTH = 1_024

    def self.call(user_agent)
      normalized_user_agent = user_agent.to_s[0, MAX_USER_AGENT_LENGTH]

      Result.new(
        device_type: device_type(normalized_user_agent),
        browser_type: browser_type(normalized_user_agent)
      )
    end

    class << self
      private

      def device_type(user_agent)
        return "tablet" if user_agent.match?(/iPad|Tablet|Kindle|Silk|Android(?!.*Mobile)/i)
        return "smartphone" if user_agent.match?(/Mobile|iPhone|iPod|Android/i)

        "pc"
      end

      def browser_type(user_agent)
        return "edge" if user_agent.match?(/Edg(?:e|A|iOS)?\//i)
        return "firefox" if user_agent.match?(/Firefox|FxiOS/i)
        return "chrome" if user_agent.match?(/Chrome|CriOS/i)
        return "safari" if user_agent.match?(/Safari/i)

        "other"
      end
    end
  end
end
