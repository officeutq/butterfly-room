# frozen_string_literal: true

require "digest"
require "json"

module StreamSessions
  class LegacyPublisherBackfillService
    KIND = "legacy_creator_backfill"
    PUBLISHER_FIELDS = %w[actual_publisher_user_id actual_publisher_source actual_publisher_recorded_at actual_publisher_evidence].freeze
    SNAPSHOT_FIELDS = (%w[id store_id booth_id started_by_cast_user_id status started_at broadcast_started_at ended_at
      created_at updated_at publisher_generation current_publisher_connection_id] + PUBLISHER_FIELDS).freeze

    class Error < StandardError; end

    # Repeatable Readで対象と金額を同じ時点から読み、DBへの書き込み自体を禁止する。
    def plan(git_commit:)
      validate_git_commit!(git_commit)
      ensure_no_outer_transaction!
      manifest = StreamSession.transaction(isolation: :repeatable_read) do
        connection.execute("SET TRANSACTION READ ONLY")
        cutoff = connection.select_value("SELECT CURRENT_TIMESTAMP").to_time.utc
        maximum_id = StreamSession.maximum(:id) || 0
        entries = []
        excluded = []
        current_ids = Booth.where.not(current_stream_session_id: nil).pluck(:current_stream_session_id).to_set

        StreamSession.where(id: ..maximum_id).find_each do |session|
          reason = exclusion_reason(session, cutoff: cutoff, current: current_ids.include?(session.id))
          if reason
            excluded << { "id" => session.id, "reason" => reason }
          else
            entries << { "before" => snapshot(session), "after" => proposed_values(session), "impact" => impact(session) }
          end
        end

        {
          "schema_version" => 1, "kind" => KIND, "environment" => Rails.env.to_s,
          "database_sha256" => database_sha256, "git_commit" => git_commit,
          "cutoff" => cutoff.iso8601(6), "maximum_id" => maximum_id,
          "entries" => entries, "excluded" => excluded,
          "excluded_counts" => excluded.map { |entry| entry.fetch("reason") }.tally
        }
      end
      manifest.merge("sha256" => self.class.checksum(manifest))
    end

    # 一覧に載ったIDだけを処理する。通知blockは行ごとのcommit後に呼び、中断時も確定済み行を再処理しない。
    def run(manifest:, mode:, confirmation:, git_commit:)
      ensure_no_outer_transaction!
      validate_manifest!(manifest, confirmation: confirmation)
      validate_git_commit!(git_commit)
      raise Error, "mode must be apply or restore" unless %w[apply restore].include?(mode)

      results = manifest.fetch("entries").map do |entry|
        result = process_entry(entry, manifest: manifest, mode: mode, git_commit: git_commit)
        yield result if block_given?
        result
      end
      { "mode" => mode, "manifest_sha256" => manifest.fetch("sha256"), "status_counts" => results.map { |r| r.fetch("status") }.tally }
    end

    def self.checksum(manifest)
      Digest::SHA256.hexdigest(JSON.generate(canonical(manifest.except("sha256"))))
    end

    def self.canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [ key, canonical(value.fetch(key)) ] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    private

    def process_entry(entry, manifest:, mode:, git_commit:)
      before = entry.fetch("before")
      status = StreamSession.transaction do
        booth = Booth.lock.find_by(id: before.fetch("booth_id"))
        session = StreamSession.lock.find_by(id: before.fetch("id"))
        if booth.nil? || session.nil?
          "skipped_missing"
        elsif Booth.where(current_stream_session_id: session.id).exists?
          "skipped_current_reference"
        elsif mode == "restore"
          restore_entry(session, entry: entry, manifest: manifest)
        else
          apply_entry(session, entry: entry, manifest: manifest, git_commit: git_commit)
        end
      end
      { "id" => before.fetch("id"), "status" => status }
    end

    def apply_entry(session, entry:, manifest:, git_commit:)
      return "already_applied" if applied_record?(session, entry: entry, manifest: manifest)
      return "skipped_changed" unless snapshot(session) == entry.fetch("before")
      return "skipped_ineligible" if exclusion_reason(session, cutoff: Time.iso8601(manifest.fetch("cutoff")), current: false)
      return "skipped_impact_changed" unless impact(session) == entry.fetch("impact")

      values = entry.fetch("after").merge("actual_publisher_recorded_at" => Time.current.utc.iso8601(6))
      session.assign_attributes(values.merge("actual_publisher_evidence" => evidence(entry, manifest: manifest, values: values, git_commit: git_commit)))
      session.save!(touch: false)
      "applied"
    end

    def restore_entry(session, entry:, manifest:)
      return "already_restored" if snapshot(session) == entry.fetch("before")
      return "skipped_changed" unless applied_record?(session, entry: entry, manifest: manifest)

      session.assign_attributes(entry.fetch("before").slice(*PUBLISHER_FIELDS))
      session.save!(touch: false)
      "restored"
    end

    def applied_record?(session, entry:, manifest:)
      current = snapshot(session)
      return false unless current.except(*PUBLISHER_FIELDS) == entry.fetch("before").except(*PUBLISHER_FIELDS)
      return false unless current.slice(*entry.fetch("after").keys) == entry.fetch("after")
      return false unless session.actual_publisher_recorded_at

      saved = session.actual_publisher_evidence
      return false unless saved["git_commit"].is_a?(String) && saved.fetch("git_commit").match?(/\A[0-9a-f]{7,40}\z/)

      values = entry.fetch("after").merge("actual_publisher_recorded_at" => current.fetch("actual_publisher_recorded_at"))
      saved == evidence(entry, manifest: manifest, values: values, git_commit: saved.fetch("git_commit"))
    end

    def evidence(entry, manifest:, values:, git_commit:)
      {
        "kind" => KIND, "schema_version" => 1, "manifest_sha256" => manifest.fetch("sha256"),
        "git_commit" => git_commit, "before" => entry.fetch("before").slice(*PUBLISHER_FIELDS), "after" => values
      }
    end

    def snapshot(session)
      session.attributes.slice(*SNAPSHOT_FIELDS).transform_values do |value|
        value.respond_to?(:iso8601) ? value.to_time.utc.iso8601(6) : value
      end
    end

    def proposed_values(session)
      { "actual_publisher_user_id" => session.started_by_cast_user_id, "actual_publisher_source" => KIND }
    end

    def exclusion_reason(session, cutoff:, current:)
      return "existing_publisher_record" if session.actual_publisher_user_id || session.actual_publisher_source ||
        session.actual_publisher_recorded_at || session.actual_publisher_evidence.present?
      return "not_ended" unless session.ended?
      return "missing_broadcast_start" unless session.broadcast_started_at
      return "inconsistent_end" unless session.ended_at && session.ended_at >= session.broadcast_started_at
      return "outside_cutoff" if session.created_at > cutoff || session.ended_at > cutoff
      return "current_reference" if current

      nil
    end

    def impact(session)
      ledger = StoreLedgerEntry.where(stream_session_id: session.id)
      {
        "from_user_id" => nil, "to_user_id" => session.started_by_cast_user_id,
        "lifetime_consumed_points" => ledger.sum(:points), "ledger_count" => ledger.count,
        "lifetime_broadcast_seconds" => session.broadcast_duration_seconds,
        "store_points_change" => 0, "booth_points_change" => 0
      }
    end

    def validate_manifest!(manifest, confirmation:)
      raise Error, "invalid manifest" unless manifest.is_a?(Hash) && manifest["schema_version"] == 1 && manifest["kind"] == KIND
      digest = self.class.checksum(manifest)
      raise Error, "manifest checksum or confirmation mismatch" unless digest == manifest["sha256"] && digest == confirmation
      raise Error, "manifest environment mismatch" unless manifest["environment"] == Rails.env.to_s && manifest["database_sha256"] == database_sha256
      validate_git_commit!(manifest["git_commit"])
      cutoff = Time.iso8601(manifest.fetch("cutoff"))
      maximum_id = manifest.fetch("maximum_id")
      raise Error, "invalid maximum id" unless maximum_id.is_a?(Integer) && maximum_id >= 0
      entries = manifest.fetch("entries")
      raise Error, "invalid entries" unless entries.is_a?(Array)
      ids = entries.map do |entry|
        before = entry.fetch("before")
        raise Error, "invalid before values" unless before.is_a?(Hash) && before.keys.sort == SNAPSHOT_FIELDS.sort
        id = before.fetch("id")
        raise Error, "invalid entry id" unless id.is_a?(Integer) && id.positive? && id <= maximum_id
        raise Error, "invalid creator" unless before["started_by_cast_user_id"].is_a?(Integer) && before["started_by_cast_user_id"].positive?
        raise Error, "invalid target" unless %w[booth_id store_id].all? { |key| before[key].is_a?(Integer) && before[key].positive? }
        raise Error, "invalid publisher values" unless before.slice(*PUBLISHER_FIELDS) == PUBLISHER_FIELDS.to_h { |key| [ key, key == "actual_publisher_evidence" ? {} : nil ] }
        expected = { "actual_publisher_user_id" => before.fetch("started_by_cast_user_id"), "actual_publisher_source" => KIND }
        raise Error, "invalid proposed values" unless entry["after"] == expected && entry["impact"].is_a?(Hash)
        raise Error, "invalid ended history" unless before["status"] == "ended" && Time.iso8601(before.fetch("ended_at")) >= Time.iso8601(before.fetch("broadcast_started_at"))
        raise Error, "entry outside cutoff" if Time.iso8601(before.fetch("created_at")) > cutoff || Time.iso8601(before.fetch("ended_at")) > cutoff
        id
      end
      raise Error, "duplicate entry ids" unless ids.uniq == ids
    rescue KeyError, TypeError, ArgumentError
      raise Error, "invalid manifest structure"
    end

    def validate_git_commit!(value)
      raise Error, "git commit must be a 7-40 character lowercase SHA" unless value.is_a?(String) && value.match?(/\A[0-9a-f]{7,40}\z/)
    end

    def database_sha256
      config = StreamSession.connection_db_config.configuration_hash.slice(:adapter, :host, :port, :database).stringify_keys
      Digest::SHA256.hexdigest(JSON.generate(self.class.canonical(config)))
    end

    def connection
      StreamSession.connection
    end

    def ensure_no_outer_transaction!
      raise Error, "run outside an existing transaction" if connection.transaction_open?
    end
  end
end
