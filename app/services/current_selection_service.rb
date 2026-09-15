# frozen_string_literal: true

class CurrentSelectionService
  PURPOSES = %i[normalize require_booth require_store select_booth select_store invitation_accepted].freeze

  Result = Struct.new(:booth, :store, :booths, :stores, :broadcast, :error, keyword_init: true) do
    def success?
      error.nil?
    end

    def booth_switchable?
      success? && broadcast.nil? && booths.many?
    end

    def store_switchable?
      success? && broadcast.nil? && stores.many?
    end

    def booth_fixed?
      success? && (broadcast.present? || booths.one?)
    end

    def store_fixed?
      success? && (broadcast.present? || stores.one?)
    end
  end

  def initialize(actor:, current_booth_id: nil, current_store_id: nil, purpose: :normalize, target_id: nil)
    raise ArgumentError, "Unknown selection purpose" unless PURPOSES.include?(purpose)

    @actor_id = actor&.id
    @current_booth_id = current_booth_id
    @current_store_id = current_store_id
    @purpose = purpose
    @target_id = target_id
  end

  def call
    ApplicationRecord.uncached do
      @actor = User.active.find_by(id: @actor_id) if @actor_id
      @result = Result.new(booths: selectable_booths, stores: selectable_stores)
      @result.booth = find_candidate(@result.booths, @current_booth_id)
      @result.store = @result.booth&.store || find_candidate(@result.stores, @current_store_id)
      normalize_selection
      apply_requested_selection if @result.success?
      @result
    end
  rescue StreamSession::CurrentBroadcastInconsistent
    @result.error = :broadcast_inconsistent
    @result
  end

  private

  def selectable_booths
    return [] unless @actor&.at_least?(:cast)

    booths = if @actor.system_admin?
      Booth.all
    elsif @actor.store_admin?
      Booth.where(store_id: admin_store_ids)
    else
      Booth.active.where(id: BoothCast.where(cast_user_id: @actor.id).select(:booth_id))
    end
    booths.includes(:store).order(:id).to_a
  end

  def selectable_stores
    return [] unless @actor&.at_least?(:store_admin)

    stores = @actor.system_admin? ? Store.all : Store.where(id: admin_store_ids)
    stores.order(:id).to_a
  end

  def admin_store_ids
    StoreMembership.where(user_id: @actor.id, membership_role: :admin).select(:store_id)
  end

  def find_candidate(candidates, id)
    candidates.find { |candidate| candidate.id.to_s == id.to_s } if id.present?
  end

  def normalize_selection
    broadcast = StreamSession.current_broadcast_for_selection(@actor)
    if broadcast
      booth = find_candidate(@result.booths, broadcast.booth_id)
      unless booth
        @result.error = :broadcast_inconsistent
        return
      end

      @result.broadcast = broadcast
      select_booth(booth)
      return
    end

    @result.store ||= @result.stores.first if @result.stores.one?
    return unless @result.booths.one?

    booth = @result.booths.first
    # 別店舗の管理中は未設定を維持し、ブースが必要な操作で初めて自動設定する（D01）。
    return if @result.booth.nil? && @result.store && @result.store.id != booth.store_id && @purpose != :require_booth

    select_booth(booth)
  end

  def apply_requested_selection
    case @purpose
    when :select_booth, :invitation_accepted
      target = find_candidate(@result.booths, @target_id)
      if target.nil? || (@purpose == :invitation_accepted && !@actor&.cast?)
        @result.error = :not_selectable
      elsif @result.broadcast && (@result.booth.id != target.id || @purpose == :invitation_accepted)
        @result.error = :broadcast_fixed
      else
        select_booth(target)
      end
    when :select_store
      target = find_candidate(@result.stores, @target_id)
      if target.nil?
        @result.error = :not_selectable
      elsif @result.broadcast && @result.store.id != target.id
        @result.error = :broadcast_fixed
      elsif @result.store&.id != target.id
        @result.store = target
        @result.booth = nil
        sole_booth = @result.booths.first if @result.booths.one?
        select_booth(sole_booth) if sole_booth&.store_id == target.id
      end
    end
  end

  def select_booth(booth)
    @result.booth = booth
    @result.store = booth.store
  end
end
