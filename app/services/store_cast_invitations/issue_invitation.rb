# frozen_string_literal: true

module StoreCastInvitations
  class IssueInvitation
    Result = Struct.new(:invitation, :token, keyword_init: true)

    def self.call!(store:, invited_by_user:, note: nil)
      new(store:, invited_by_user:, note:).call!
    end

    def initialize(store:, invited_by_user:, note:)
      @store = store
      @invited_by_user = invited_by_user
      @note = note
    end

    def call!
      token = StoreCastInvitation.generate_token
      digest = StoreCastInvitation.digest_for(token)

      invitation = nil

      ActiveRecord::Base.transaction do
        invitation = StoreCastInvitation.create!(
          store: @store,
          invited_by_user: @invited_by_user,
          token_digest: digest,
          expires_at: 24.hours.from_now,
          note: @note.presence
        )
      end

      Result.new(invitation: invitation, token: token)
    end
  end
end
