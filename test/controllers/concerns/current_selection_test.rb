require "test_helper"

class CurrentSelectionTest < ActiveSupport::TestCase
  class SelectionController
    include CurrentSelection

    attr_reader :current_user, :session

    def initialize(user, session)
      @current_user = user
      @session = session
    end

    def select(**options)
      result = resolve_current_selection(**options)
      save_current_selection(result)
      result
    end
  end

  setup do
    @actor = User.create!(email: "selection-save@example.com", password: "password", role: :store_admin)
    @store_a = Store.create!(name: "Saved A")
    @store_b = Store.create!(name: "Saved B")
    [ @store_a, @store_b ].each { |store| StoreMembership.create!(store: store, user: @actor, membership_role: :admin) }
    @booth = Booth.create!(store: @store_a, name: "Saved booth")
    @session = { current_store_id: @store_a.id, current_booth_id: @booth.id, unrelated: "keep" }
    @controller = SelectionController.new(@actor, @session)
  end

  test "店舗変更時の解除とブース必要操作での再設定を同じ保存箇所で行う" do
    result = @controller.select(purpose: :select_store, target_id: @store_b.id)
    assert result.success?
    assert_equal({ current_store_id: @store_b.id, unrelated: "keep" }, @session)
    @controller.select
    assert_equal({ current_store_id: @store_b.id, unrelated: "keep" }, @session)
    @controller.select(purpose: :require_booth)
    assert_equal({ current_store_id: @store_a.id, current_booth_id: @booth.id, unrelated: "keep" }, @session)
  end

  test "拒否された切替は元の保存値を変更しない" do
    before = @session.dup
    result = @controller.select(purpose: :select_booth, target_id: -1)
    assert_equal :not_selectable, result.error
    assert_equal before, @session
  end

  test "無効化された選択だけを解除し他のログイン情報は保持する" do
    StoreMembership.where(user: @actor).delete_all
    result = @controller.select
    assert result.success?
    assert_equal({ unrelated: "keep" }, @session)
  end

  test "同じ店舗の再確認ではブース選択を保持する" do
    before = @session.dup
    @controller.select(purpose: :select_store, target_id: @store_a.id)
    assert_equal before, @session
  end
end
