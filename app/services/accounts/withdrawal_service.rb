# frozen_string_literal: true

module Accounts
  class WithdrawalService
    class Error < StandardError; end
    class NotAllowed < Error; end

    Result = Struct.new(:user, :already_withdrawn, keyword_init: true)

    def initialize(user:)
      @user = user
    end

    def call!
      raise NotAllowed if @user.blank? || @user.system_admin?

      result = nil

      ActiveRecord::Base.transaction do
        user = User.lock.find(@user.id)

        if user.deleted?
          result = Result.new(user:, already_withdrawn: true)
          next
        end

        case user.role.to_sym
        when :customer
          # ポイント、購入、注文、問い合わせ等の履歴は保持する。
        when :cast
          remove_all_cast_memberships!(user)
        when :store_admin
          clean_up_admin_stores!(user)
        else
          raise NotAllowed
        end

        user.update!(deleted_at: Time.current)
        result = Result.new(user:, already_withdrawn: false)
      end

      result
    rescue StandardError => e
      Rails.logger.error(
        "[AccountWithdrawal] #{e.class}: #{e.message} " \
        "user_id=#{@user&.id} role=#{@user&.role}"
      )
      raise
    end

    private

    def remove_all_cast_memberships!(user)
      StoreMembership
        .where(user_id: user.id, membership_role: :cast)
        .order(:store_id, :id)
        .to_a
        .each do |membership|
          StoreMemberships::RemoveCastService.new(
            membership:,
            actor: user
          ).call!
        end
    end

    def clean_up_admin_stores!(user)
      stores = locked_admin_stores(user)

      stores.each do |store|
        next if other_active_admin_exists?(store, user)

        close_store!(store, user)
      end
    end

    def locked_admin_stores(user)
      store_ids = StoreMembership
                    .admin_only
                    .where(user_id: user.id)
                    .order(:store_id)
                    .pluck(:store_id)

      Store.where(id: store_ids).order(:id).lock.to_a
    end

    def other_active_admin_exists?(store, user)
      StoreMembership
        .admin_only
        .joins(:user)
        .merge(User.active)
        .where(store_id: store.id)
        .where.not(user_id: user.id)
        .exists?
    end

    def close_store!(store, actor)
      now = Time.current
      store.update!(published: false)

      StoreMembership
        .where(store_id: store.id, membership_role: :cast)
        .order(:id)
        .to_a
        .each do |membership|
          StoreMemberships::RemoveCastService.new(
            membership:,
            actor:
          ).call!
        end

      store.booths.active.order(:id).to_a.each do |booth|
        Booths::CloseAndArchiveService.new(booth:, actor:).call!
      end

      invalidate_unused_invitations!(store.store_cast_invitations, now)
      invalidate_unused_invitations!(store.store_admin_invitations, now)
    end

    def invalidate_unused_invitations!(scope, now)
      scope
        .where(used_at: nil)
        .where("expires_at > ?", now)
        .update_all(expires_at: now, updated_at: now)
    end
  end
end
