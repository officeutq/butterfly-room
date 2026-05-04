# frozen_string_literal: true

module Admin
  class CastsController < Admin::BaseController
    before_action :require_current_store!

    def index
      @cast_memberships =
        StoreMembership
          .includes(user: { booth_casts: :booth })
          .where(store_id: current_store.id, membership_role: :cast)
          .order(:id)
    end

    def destroy
      membership =
        StoreMembership
          .where(store_id: current_store.id, membership_role: :cast)
          .find(params[:id])

      archived_count = archive_cast_booths_for!(membership)

      membership.destroy!

      notice =
        if archived_count.positive?
          "キャスト登録を解除し、関連ブース#{archived_count}件をアーカイブしました"
        else
          "キャスト登録を解除しました"
        end

      redirect_to admin_casts_path, notice: notice
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue StreamSessions::EndService::AlreadyEnded
      redirect_to admin_casts_path, alert: "配信セッションは既に終了済みですが、状態が整っていないため解除できません。状態を確認してください。"
    rescue StreamSessions::EndService::NotAuthorized
      head :forbidden
    rescue => e
      redirect_to admin_casts_path, alert: e.message
    end

    private

    def archive_cast_booths_for!(membership)
      booths =
        current_store
          .booths
          .joins(:booth_casts)
          .where(booth_casts: { cast_user_id: membership.user_id })
          .distinct

      archived_count = 0

      booths.find_each do |booth|
        next if booth.archived?

        end_stream_session_if_needed!(booth)

        Booth.transaction do
          booth = Booth.lock.find(booth.id)
          next if booth.archived?

          if booth.current_stream_session_id.present? || !booth.offline?
            raise "ブース##{booth.id}（#{booth.name}）の状態が整っていないため、アーカイブできません。"
          end

          booth.update!(archived_at: Time.current)
          archived_count += 1
        end
      end

      archived_count
    end

    def end_stream_session_if_needed!(booth)
      booth.reload

      case booth.status.to_sym
      when :offline
        if booth.current_stream_session_id.present?
          raise "ブース##{booth.id}（#{booth.name}）は配信セッション情報が残っているため、安全にアーカイブできません。状態を確認してください。"
        end
      when :standby, :live, :away
        stream_session = StreamSession.find_by(id: booth.current_stream_session_id)
        raise if stream_session.blank?

        StreamSessions::ForceEndService.new(
          stream_session: stream_session,
          actor: current_user
        ).call
      else
        raise "ブース##{booth.id}（#{booth.name}）の状態を判定できないため、アーカイブできません。"
      end
    end
  end
end
