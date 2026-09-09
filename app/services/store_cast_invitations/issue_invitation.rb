# frozen_string_literal: true

module StoreCastInvitations
  class IssueInvitation
    Result = Struct.new(:invitation, :token, keyword_init: true)

    def self.call!(store:, invited_by_user:, note: nil, request_key: nil, url_builder: nil)
      new(store:, invited_by_user:, note:, request_key:, url_builder:).call!
    end

    def initialize(store:, invited_by_user:, note:, request_key:, url_builder:)
      @store = store
      @invited_by_user = invited_by_user
      @note = note
      @request_key = request_key
      @url_builder = url_builder
    end

    def call!
      token = StoreCastInvitation.generate_token
      digest = StoreCastInvitation.digest_for(token)

      invitation = nil

      ActiveRecord::Base.transaction do
        @invited_by_user.lock!
        if @request_key.present?
          existing = StoreCastInvitation.find_by(invited_by_user: @invited_by_user, request_key: @request_key)
          if existing
            raise ArgumentError, "招待の対象店舗が一致しません" if existing.store_id != @store.id
            return Result.new(invitation: existing, token: nil)
          end
        end
        invitation = StoreCastInvitation.create!(
          store: @store,
          invited_by_user: @invited_by_user,
          token_digest: digest,
          expires_at: 1.week.from_now,
          note: @note.presence,
          request_key: @request_key,
          issued_url: @url_builder&.call(token)
        )
        @store.with_lock { @store.advance_onboarding_to_create_invite! }
      end

      Result.new(invitation: invitation, token: token)
    end
  end
end
