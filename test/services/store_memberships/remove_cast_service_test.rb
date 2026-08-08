# frozen_string_literal: true

require "test_helper"

class StoreMemberships::RemoveCastServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Removal Store")
    @other_store = Store.create!(name: "Other Store")
    @admin = User.create!(email: "removal-admin@example.com", password: "password", role: :store_admin)
    @cast = User.create!(email: "removal-cast@example.com", password: "password", role: :cast)
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    @membership = StoreMembership.create!(store: @store, user: @cast, membership_role: :cast)
    @other_membership = StoreMembership.create!(store: @other_store, user: @cast, membership_role: :cast)
  end

  test "archives only related booths and removes the target membership" do
    booth = Booth.create!(store: @store, name: "Removal Booth", status: :offline)
    other_booth = Booth.create!(store: @other_store, name: "Other Booth", status: :offline)
    BoothCast.create!(booth:, cast_user: @cast)
    BoothCast.create!(booth: other_booth, cast_user: @cast)

    result = service.call!

    assert_equal 1, result.archived_booths_count
    assert result.membership_removed
    assert booth.reload.archived?
    assert_not other_booth.reload.archived?
    assert_not StoreMembership.exists?(@membership.id)
    assert StoreMembership.exists?(@other_membership.id)
  end

  test "forces an active stream to end before archiving" do
    booth = Booth.create!(store: @store, name: "Live Booth", status: :live)
    BoothCast.create!(booth:, cast_user: @cast)
    stream_session = StreamSession.create!(
      booth:,
      store: @store,
      started_by_cast_user: @cast,
      status: :live,
      started_at: Time.current
    )
    booth.update!(current_stream_session: stream_session)

    service.call!

    assert stream_session.reload.ended?
    assert stream_session.ended_at.present?
    assert booth.reload.offline?
    assert booth.archived?
    assert_nil booth.current_stream_session_id
  end

  test "a repeated call is a no-op" do
    first = service.call!
    second = service.call!

    assert first.membership_removed
    assert_not second.membership_removed
    assert_equal 0, second.archived_booths_count
  end

  test "an unrelated store admin is rejected" do
    other_admin = User.create!(email: "other-removal-admin@example.com", password: "password", role: :store_admin)

    assert_raises StoreMemberships::RemoveCastService::NotAuthorized do
      StoreMemberships::RemoveCastService.new(membership: @membership, actor: other_admin).call!
    end

    assert StoreMembership.exists?(@membership.id)
  end

  private

  def service
    StoreMemberships::RemoveCastService.new(membership: @membership, actor: @admin)
  end
end
