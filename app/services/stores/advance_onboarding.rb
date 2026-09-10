module Stores
  class AdvanceOnboarding
    def self.call!(store:, action:)
      store.with_lock do
        case action
        when :dashboard then store.advance_onboarding_to_setup_drinks!
        when :skip then store.skip_onboarding!
        else raise ArgumentError, "不明な操作です"
        end
      end
    end
  end
end
