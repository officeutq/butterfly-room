# frozen_string_literal: true

module StoreMemberships
  class RemoveCastService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class InvalidMembership < Error; end

    Result = Struct.new(:archived_booths_count, :membership_removed, keyword_init: true)

    def initialize(membership:, actor:)
      @membership = membership
      @actor = actor
    end

    def call!
      membership = StoreMembership.find_by(id: @membership.id)
      return Result.new(archived_booths_count: 0, membership_removed: false) if membership.blank?

      raise InvalidMembership unless membership.cast?

      authorize!(membership)

      archived_count = 0
      cast_booths_for(membership).find_each do |booth|
        result = Booths::CloseAndArchiveService.new(booth:, actor: @actor).call!
        archived_count += 1 if result.archived
      end

      membership.destroy!

      Result.new(
        archived_booths_count: archived_count,
        membership_removed: true
      )
    end

    private

    def authorize!(membership)
      raise NotAuthorized if @actor.blank? || @actor.deleted?
      return if @actor.system_admin?
      return if @actor.cast? && @actor.id == membership.user_id
      return if @actor.store_admin? && @actor.admin_of_store?(membership.store_id)

      raise NotAuthorized
    end

    def cast_booths_for(membership)
      membership
        .store
        .booths
        .joins(:booth_casts)
        .where(booth_casts: { cast_user_id: membership.user_id })
        .distinct
        .order(:id)
    end
  end
end
