# frozen_string_literal: true

module Logs
  class ArchiveService
    MAX_LIMIT = 10_000
    Result = Data.define(:candidate_count, :archived_count, :cutoff, :applied)

    def self.call(kind:, limit: 1000, apply: false, now: Time.current)
      model, days = { errors: [ ErrorLog, 90 ], changes: [ ChangeLog, 365 ] }.fetch(kind)
      size = Integer(limit.to_s, exception: false)
      raise ArgumentError, "limitは1〜#{MAX_LIMIT}を指定してください" unless size && (1..MAX_LIMIT).cover?(size)
      raise ArgumentError, "applyは真偽値で指定してください" unless apply == true || apply == false

      cutoff = now - days.days
      scope = model.active.where("occurred_at < ?", cutoff)
      ids = scope.order(:occurred_at, :id).limit(size).pluck(:id)
      count = apply && ids.any? ? scope.where(id: ids).update_all(archived_at: now) : 0
      Result.new(candidate_count: ids.size, archived_count: count, cutoff: cutoff, applied: apply)
    end
  end
end
