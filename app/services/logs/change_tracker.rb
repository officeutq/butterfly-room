# frozen_string_literal: true

module Logs
  class ChangeTracker
    def initialize(actor_user:, source:, request_id:)
      @actor_user = actor_user
      @source = source
      @request_id = request_id
    end

    # Called on the saving instance after its row lock, before assigning changes.
    def capture_before(record)
      @created = record.new_record?
      @before = @created ? {} : snapshot(record)
    end

    def record!(record)
      raise ArgumentError, "change snapshot missing" unless @before

      after = snapshot(record)
      differences = after.to_h { |key, value| [ key, [ @before[key], value ] ] }
      RecordChangeService.call(
        record:, changes: differences, actor_user: @actor_user, source: @source,
        request_id: @request_id, action: @created ? "created" : "updated"
      )
    rescue ActiveRecord::RecordInvalid
      record.errors.add(:base, "変更履歴を保存できなかったため、更新を取り消しました")
      raise ActiveRecord::RecordInvalid, record
    end

    private

    def snapshot(record)
      fields = Sanitizer::FIELDS.fetch(record.class.base_class.name)
      values = record.attributes.slice(*fields)
      purpose = record.image_attachment_purpose_for(:thumbnail)
      values["thumbnail"] = {
        "source_blob_id" => record.public_send(purpose.source_attachment).attachment&.blob_id,
        "display_blob_id" => record.public_send(purpose.display_attachment).attachment&.blob_id
      }
      values["thumbnail"] = nil if values["thumbnail"].values.all?(&:nil?)
      values
    end
  end
end
