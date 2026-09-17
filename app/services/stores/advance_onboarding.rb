module Stores
  class AdvanceOnboarding
    def self.allowed?(store:, actor:)
      return false unless store && actor && !actor.deleted? && actor.at_least?(:store_admin)

      actor.system_admin? || actor.admin_of_store?(store.id)
    end

    def self.call!(store:, actor:, action:)
      return unless allowed?(store: store, actor: actor)

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
