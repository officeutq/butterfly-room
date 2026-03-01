# frozen_string_literal: true

require "test_helper"

class StreamSessionPolicyBoothCastsTest < ActiveSupport::TestCase
  Record = Struct.new(:booth, :started_by_cast_user_id, :store)

  setup do
    @store = Store.create!(name: "store1")
    @booth = Booth.create!(store: @store, name: "booth1", status: :offline)

    @cast1 = User.create!(email: "cast1_pol@example.com", password: "password", role: :cast)
    @cast2 = User.create!(email: "cast2_pol@example.com", password: "password", role: :cast)

    # cast の基本条件（at_least cast）を満たすため、roleのみでOK
    # 「担当未設定の暫定措置」を避けるため、booth_casts を作って primary を確定する
    BoothCast.create!(booth: @booth, cast_user: @cast1)

    @record = Record.new(@booth, @cast1.id, @store)
  end

  test "linked cast can publish when primary is set" do
    policy = Authorization::StreamSessionPolicy.new(@cast1, @record)
    assert policy.publish_token?
  end

  test "unlinked cast cannot publish when primary is set" do
    policy = Authorization::StreamSessionPolicy.new(@cast2, @record)
    assert_not policy.publish_token?
  end
end
