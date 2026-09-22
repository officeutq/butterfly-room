# frozen_string_literal: true

module StoreAdminInvitations
  class IssueInvitation
    Result = Struct.new(:invitation, :token, keyword_init: true)
    class NotAuthorized < StandardError; end

    def self.call!(store:, invited_by_user:, request_key: nil, url_builder: nil)
      new(store:, invited_by_user:, request_key:, url_builder:).call!
    end

    def initialize(store:, invited_by_user:, request_key:, url_builder:)
      @store = store
      @invited_by_user = invited_by_user
      @request_key = request_key
      @url_builder = url_builder
    end

    def call!
      token = StoreAdminInvitation.generate_token
      digest = StoreAdminInvitation.digest_for(token)

      invitation = nil

      ActiveRecord::Base.transaction do
        @invited_by_user.lock!
        unless !@invited_by_user.deleted? && (@invited_by_user.system_admin? ||
            (@invited_by_user.store_admin? && @invited_by_user.admin_of_store?(@store.id)))
          raise NotAuthorized, "この店舗の招待を発行する権限がありません"
        end
        if @request_key.present?
          existing = StoreAdminInvitation.find_by(invited_by_user: @invited_by_user, request_key: @request_key)
          if existing
            raise ArgumentError, "招待の対象店舗が一致しません" if existing.store_id != @store.id
            return Result.new(invitation: existing, token: nil)
          end
        end
        invitation = StoreAdminInvitation.create!(
          store: @store,
          invited_by_user: @invited_by_user,
          token_digest: digest,
          expires_at: 1.week.from_now,
          request_key: @request_key,
          issued_url: @url_builder&.call(token)
        )
      end

      Result.new(invitation: invitation, token: token)
    end
  end
end
