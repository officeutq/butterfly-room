# frozen_string_literal: true

module Logs
  class RecordChangeService
    def self.call(record:, changes:, actor_user: nil, source: "application", request_id: nil, action: "updated")
      target_type = record.class.base_class.name
      raise ArgumentError, "unsupported log target" unless ChangeLog::TARGET_TYPES.include?(target_type)
      raise ArgumentError, "business transaction required" unless record.class.connection.transaction_open?

      differences = changes.select { |_key, values| values.is_a?(Array) && values.size == 2 && values[0] != values[1] }
      data = Sanitizer.change_data(target_type, differences)
      return if data.empty? && action != "created"

      ChangeLog.create!(
        target_type:, target_id: record.id, action:, change_data: data,
        occurred_at: Time.current, actor_user_id: actor_user&.id,
        store_id: target_type == "Store" ? record.id : record.store_id,
        source:, request_id: Sanitizer.identifier(request_id)
      )
    end
  end
end
