# frozen_string_literal: true

require "digest"

module StreamSessions
  class LegacyBroadcasterBackfill
    SNAPSHOT_FIELDS = %w[id booth_id store_id started_by_cast_user_id status created_at started_at broadcast_started_at ended_at publisher_protocol].freeze

    def self.preview(cutoff:)
      cutoff = Time.iso8601(cutoff.to_s)
      raise ArgumentError, "基準時刻は過去を指定してください" if cutoff > Time.current

      rows = StreamSession.order(:id).map do |session|
        reason = exclusion_reason(session, cutoff: cutoff)
        {
          "snapshot" => session.attributes.slice(*SNAPSHOT_FIELDS).as_json,
          "reason" => reason, "from_user_id" => session.broadcast_started_by_user_id,
          "from_source" => session.broadcast_identity_source, "booth_status" => session.booth.status,
          "to_user_id" => reason ? nil : session.started_by_cast_user_id,
          "sales_points" => StoreLedgerEntry.where(stream_session_id: session.id).sum(:points),
          "broadcast_seconds" => session.broadcast_duration_seconds,
          "consumed_comment_ids" => session.comments.where(kind: Comment::KIND_DRINK_CONSUMED).pluck(:id)
        }
      end
      { "version" => 1, "cutoff" => cutoff.iso8601(6), "rows" => rows,
        "counts" => rows.group_by { |r| r["reason"] || "eligible" }.transform_values(&:size) }
    end

    def self.exclusion_reason(session, cutoff:)
      return "new_session" if session.publisher_protocol.present? || session.created_at > cutoff || session.started_at > cutoff
      return "already_recorded" if session.broadcast_started_by_user_id.present? || session.broadcast_identity_source.present?
      return "not_ended_at_cutoff" unless session.ended? && session.ended_at && session.ended_at <= cutoff
      return "missing_broadcast_start" unless session.broadcast_started_at
      return "inconsistent_times" unless session.started_at <= session.broadcast_started_at && session.broadcast_started_at <= session.ended_at
      return "current_session_reference" if Booth.where(current_stream_session_id: session.id).exists?
      return "store_mismatch" unless session.booth.store_id == session.store_id

      nil
    end

    def initialize(manifest:)
      @manifest = manifest.deep_stringify_keys
      raise ArgumentError, "未対応の計画形式です" unless @manifest["version"] == 1 && @manifest["rows"].is_a?(Array)

      @cutoff = Time.iso8601(@manifest.fetch("cutoff"))
      @run_id = Digest::SHA256.hexdigest(JSON.generate(@manifest))
    end

    def apply
      results = []
      @manifest.fetch("rows").select { |r| r["reason"].nil? }.each do |row|
        snapshot = row.fetch("snapshot")
        StreamSession.transaction do
          Booth.lock.find(snapshot.fetch("booth_id"))
          session = StreamSession.lock.find(snapshot.fetch("id"))
          reason = self.class.exclusion_reason(session, cutoff: @cutoff)
          reason ||= "changed_since_preview" unless session.attributes.slice(*SNAPSHOT_FIELDS).as_json == snapshot
          reason ||= "invalid_destination" unless row["to_user_id"] == session.started_by_cast_user_id && row["from_user_id"].nil?
          unless reason
            session.update_columns(broadcast_started_by_user_id: session.started_by_cast_user_id,
              broadcast_identity_source: "legacy_creator_backfill",
              broadcast_identity_evidence: session.broadcast_identity_evidence.merge(
                "backfill" => { "run_id" => @run_id, "cutoff" => @cutoff.iso8601(6),
                  "from_user_id" => nil, "to_user_id" => session.started_by_cast_user_id, "recorded_at" => Time.current.iso8601(6) }))
          end
          results << { id: session.id, result: reason || "updated", run_id: @run_id }
        end
      end
      results
    end

    def rollback
      @manifest.fetch("rows").select { |r| r["reason"].nil? }.map do |row|
        StreamSession.transaction do
          session = StreamSession.lock.find(row.fetch("snapshot").fetch("id"))
          evidence = session.broadcast_identity_evidence
          matches = session.broadcast_identity_source == "legacy_creator_backfill" &&
            evidence.dig("backfill", "run_id") == @run_id && session.broadcast_started_by_user_id == row["to_user_id"] &&
            session.attributes.slice(*SNAPSHOT_FIELDS).as_json == row["snapshot"] &&
            !Booth.where(current_stream_session_id: session.id).exists?
          if matches
            session.update_columns(broadcast_started_by_user_id: nil, broadcast_identity_source: nil,
              broadcast_identity_evidence: evidence.merge("backfill_reverted_at" => Time.current.iso8601(6)))
          end
          { id: session.id, result: matches ? "reverted" : "skipped" }
        end
      end
    end
  end
end
