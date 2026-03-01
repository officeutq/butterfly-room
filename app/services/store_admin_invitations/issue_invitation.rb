# frozen_string_literal: true

module StoreAdminInvitations
  class IssueInvitation
    Result = Struct.new(:invitation, :token, keyword_init: true)

    def self.call!(store:, invited_by_user:)
      new(store:, invited_by_user:).call!
    end

    def initialize(store:, invited_by_user:)
      @store = store
      @invited_by_user = invited_by_user
    end

    def call!
      token = StoreAdminInvitation.generate_token
      digest = StoreAdminInvitation.digest_for(token)

      invitation = nil

      ActiveRecord::Base.transaction do
        invitation = StoreAdminInvitation.create!(
          store: @store,
          invited_by_user: @invited_by_user,
          token_digest: digest,
          expires_at: 24.hours.from_now
        )
      end

      Result.new(invitation: invitation, token: token)
    end
  end
end
