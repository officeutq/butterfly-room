# frozen_string_literal: true

require "digest"

module StreamSessions
  class BroadcasterEvidenceService
    # IVSが保持する範囲だけを読む。取得不能や属性欠落を「配信なし」と扱わない。
    def self.investigate(session, client: Ivs::Client.build)
      records = client.list_stage_sessions(stage_arn: session.ivs_stage_arn).flat_map do |stage_session|
        next [] if stage_session.start_time && stage_session.start_time > (session.ended_at || Time.current)
        next [] if stage_session.end_time && stage_session.end_time < session.started_at

        client.list_participants(stage_arn: session.ivs_stage_arn, session_id: stage_session.session_id).filter_map do |participant|
          attrs = participant.attributes || {}
          next unless attrs["stream_session_id"] == session.id.to_s && attrs["role"] == "publisher" && participant.published

          { stage_session_id: stage_session.session_id, participant_id: participant.participant_id,
            user_id: attrs["user_id"], user_id_consistent: participant.user_id.blank? || participant.user_id == attrs["user_id"] }
        end
      end
      ids = records.map { |r| r[:user_id] }.uniq
      complete = records.all? { |r| r[:user_id].present? && r[:user_id_consistent] && User.exists?(id: r[:user_id]) }
      classification = if records.empty? || !complete
        "unknown"
      elsif ids.size == 1
        "identified"
      else
        "ambiguous"
      end
      { stream_session_id: session.id, classification: classification, records: records,
        proposed_user_id: classification == "identified" ? ids.first.to_i : nil }
    end

    def initialize(plan:)
      @plan = plan.deep_stringify_keys
      @session = StreamSession.find(@plan.fetch("stream_session_id"))
      @user = User.find(@plan.fetch("to_user_id"))
      @digest = Digest::SHA256.hexdigest(JSON.generate(@plan))
      raise ArgumentError, "証拠の参照先と判断理由が必要です" if @plan["evidence_reference"].blank? || @plan["reason"].blank?
    end

    def preview
      raise ArgumentError, "終了済み旧配信だけを補正できます" unless @session.ended? && @session.ended_at && @session.publisher_protocol.nil?
      raise ArgumentError, "現在のブース参照が残っています" if Booth.where(current_stream_session_id: @session.id).exists?
      raise ArgumentError, "本人記録は補正対象外です" if @session.broadcast_identity_source == "ivs_confirmed"
      unless @session.broadcast_started_by_user_id == @plan.fetch("from_user_id") && @session.broadcast_identity_source == @plan.fetch("from_source")
        raise ArgumentError, "確認後に配信者が変更されています"
      end

      comments = @plan.fetch("comments", []).map do |row|
        comment = @session.comments.find(row.fetch("id"))
        unless comment.kind == Comment::KIND_DRINK_CONSUMED && comment.user_id == row.fetch("from_user_id")
          raise ArgumentError, "自動コメントの確認値が一致しません"
        end
        { id: comment.id, from_user_id: comment.user_id, to_user_id: @user.id }
      end
      { stream_session_id: @session.id, from_user_id: @session.broadcast_started_by_user_id,
        to_user_id: @user.id, reassigned_sales_points: StoreLedgerEntry.where(stream_session_id: @session.id).sum(:points),
        reassigned_seconds: @session.broadcast_duration_seconds, store_sales_delta: 0, comments: comments }
    end

    def apply
      @session.with_lock do
        evidence = @session.broadcast_identity_evidence
        return { result: "already_applied" } if evidence.fetch("corrections", []).any? { |c| c["plan_digest"] == @digest }

        result = preview
        audit = { "plan_digest" => @digest, "plan" => @plan, "recorded_at" => Time.current.iso8601(6) }
        @session.update_columns(broadcast_started_by_user_id: @user.id, broadcast_identity_source: "evidence",
          broadcast_identity_evidence: evidence.merge("corrections" => evidence.fetch("corrections", []) + [ audit ]))
        result[:comments].each do |change|
          comment = @session.comments.lock.find(change[:id])
          raise ArgumentError, "コメントが変更されています" unless comment.user_id == change[:from_user_id] && comment.kind == Comment::KIND_DRINK_CONSUMED

          comment.update_columns(user_id: @user.id, metadata: comment.metadata_hash.merge("broadcaster_correction" => audit))
        end
        result.merge(result: "updated")
      end
    end
  end
end
