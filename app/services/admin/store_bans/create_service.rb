# frozen_string_literal: true

module Admin
  module StoreBans
    class CreateService
      class Error < StandardError; end
      class UnsupportedCustomerError < Error; end
      class SourceCommentStoreMismatchError < Error; end

      Result = Data.define(:store_ban, :created)

      def initialize(store:, customer_user:, actor:, reason: nil, source_comment: nil)
        @store = store
        @customer_user = customer_user
        @actor = actor
        @reason = reason
        @source_comment = source_comment
      end

      def call
        validate!

        existing_ban = StoreBan.active.find_by(store: @store, customer_user: @customer_user)
        return Result.new(store_ban: existing_ban, created: false) if existing_ban.present?

        store_ban = StoreBan.create!(
          store: @store,
          customer_user: @customer_user,
          created_by_store_admin_user: @actor,
          reason: @reason,
          source_comment: @source_comment
        )

        Result.new(store_ban: store_ban, created: true)
      rescue ActiveRecord::RecordNotUnique
        Result.new(
          store_ban: StoreBan.active.find_by!(store: @store, customer_user: @customer_user),
          created: false
        )
      end

      private

      def validate!
        raise UnsupportedCustomerError unless @customer_user&.customer?

        return if @source_comment.blank?
        return if @source_comment.stream_session.store_id == @store.id

        raise SourceCommentStoreMismatchError
      end
    end
  end
end
