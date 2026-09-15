require "test_helper"

class CurrentSelectionServiceTest < ActiveSupport::TestCase
  setup do
    @actor = User.create!(email: "current-selection@example.com", password: "password", role: :store_admin)
    @other = User.create!(email: "other-selection@example.com", password: "password", role: :cast)
    @store_a = Store.create!(name: "A store")
    @store_b = Store.create!(name: "B store", published: false)
    [ @store_a, @store_b ].each do |store|
      StoreMembership.create!(store: store, user: @actor, membership_role: :admin)
    end
  end

  test "候補なしでは権限外の対象を補完しない" do
    result = resolve(purpose: :require_booth)
    assert result.success?
    assert_nil result.booth
    assert_nil result.store
    assert_empty result.booths
    assert_not result.booth_switchable?
    assert result.store_switchable?
  end

  test "唯一のブースを店舗と組で固定しモーダルの切替対象にしない" do
    booth = create_booth(@store_a)
    result = resolve
    assert_equal booth, result.booth
    assert_equal @store_a, result.store
    assert result.booth_fixed?
    assert_not result.booth_switchable?
    assert result.store_switchable?
  end

  test "D01 AからブースのないBへ変更して通常表示では未設定を維持する" do
    booth = create_booth(@store_a)
    result = resolve(current_booth_id: booth.id, current_store_id: @store_a.id,
      purpose: :select_store, target_id: @store_b.id)
    assert result.success?
    assert_nil result.booth
    assert_equal @store_b, result.store
    assert_not result.booth_switchable?
    %i[normalize require_store].each do |purpose|
      current = resolve(current_store_id: result.store.id, purpose: purpose)
      assert current.success?
      assert_nil current.booth
      assert_equal @store_b, current.store
    end
  end

  test "D01 BからAへの変更とBからブース必要操作では唯一のAを自動設定する" do
    booth = create_booth(@store_a)
    [ { purpose: :select_store, target_id: @store_a.id }, { purpose: :require_booth } ].each do |operation|
      result = resolve(current_store_id: @store_b.id, **operation)
      assert result.success?
      assert_equal booth, result.booth
      assert_equal @store_a, result.store
      assert_not result.booth_switchable?
    end
  end

  test "D01 複数候補は変更先店舗に一件でも勝手に自動選択しない" do
    booth_a = create_booth(@store_a)
    booth_b = create_booth(@store_b)
    result = resolve(current_booth_id: booth_a.id, purpose: :select_store, target_id: @store_b.id)
    assert result.success?
    assert_nil result.booth
    assert_equal @store_b, result.store
    required = resolve(current_store_id: @store_b.id, purpose: :require_booth)
    assert_nil required.booth
    assert_equal [ booth_a, booth_b ], required.booths
    assert required.booth_switchable?
  end

  test "同じ店舗の再確認は有効なブースを解除しない" do
    create_booth(@store_a)
    booth_b = create_booth(@store_b)
    result = resolve(current_booth_id: booth_b.id, purpose: :select_store, target_id: @store_b.id)
    assert_equal booth_b, result.booth
    assert_equal @store_b, result.store
  end

  test "複数候補は有効な選択を維持し未選択や無効を最小IDで埋めない" do
    booth_a = create_booth(@store_a)
    booth_b = create_booth(@store_b)
    assert_equal booth_b, resolve(current_booth_id: booth_b.id).booth
    [ nil, -1, "#{booth_a.id}invalid" ].each do |id|
      result = resolve(current_booth_id: id, current_store_id: @store_b.id, purpose: :require_booth)
      assert_nil result.booth
      assert_equal @store_b, result.store
      assert result.booth_switchable?
    end
  end

  test "ブースの選択成功は所属店舗も更新し参照だけでは配信を作らない" do
    booth_a = create_booth(@store_a)
    booth_b = create_booth(@store_b)
    assert_no_difference [ "StreamSession.count", "StreamPublisherConnection.count" ] do
      result = resolve(current_booth_id: booth_a.id, purpose: :select_booth, target_id: booth_b.id.to_s)
      assert result.success?
      assert_equal booth_b, result.booth
      assert_equal @store_b, result.store
    end
    assert booth_b.reload.offline?
  end

  test "不正な対象を拒否して元の有効な選択やD01の店舗を失わせない" do
    booth = create_booth(@store_a)
    outside = create_booth(Store.create!(name: "Outside"))
    [ { purpose: :select_booth, target_id: outside.id },
      { purpose: :select_booth, target_id: "#{booth.id}invalid" },
      { purpose: :select_store, target_id: outside.store_id } ].each do |operation|
      result = resolve(current_booth_id: booth.id, **operation)
      assert_equal :not_selectable, result.error
      assert_equal booth, result.booth
      assert_equal @store_a, result.store
      deferred = resolve(current_store_id: @store_b.id, **operation)
      assert_equal :not_selectable, deferred.error
      assert_nil deferred.booth
      assert_equal @store_b, deferred.store
    end
  end

  test "本人の配信中と離席中は別店舗の選択や未選択からも本人へ固定する" do
    booth_a = create_booth(@store_a)
    booth_b = create_booth(@store_b)
    session = start_broadcast(booth_a, @actor)
    %i[live away].each do |status|
      booth_a.update!(status: status)
      [ nil, booth_b.id ].each do |selected|
        result = resolve(current_booth_id: selected, current_store_id: @store_b.id)
        assert_equal booth_a, result.booth
        assert_equal @store_a, result.store
        assert_equal session, result.broadcast
        assert_not result.booth_switchable?
        assert_not result.store_switchable?
        assert result.booth_fixed?
        assert result.store_fixed?
      end
      [ { purpose: :select_booth, target_id: booth_b.id },
        { purpose: :select_store, target_id: @store_b.id } ].each do |operation|
        result = resolve(current_booth_id: booth_a.id, **operation)
        assert_equal :broadcast_fixed, result.error
        assert_equal booth_a, result.booth
        assert_equal @store_a, result.store
      end
    end
  end

  test "本人配信中はブース一件でも店舗切替の例外を適用しない" do
    booth = create_booth(@store_a)
    start_broadcast(booth, @actor)
    result = resolve(current_booth_id: booth.id, purpose: :select_store, target_id: @store_b.id)
    assert_equal :broadcast_fixed, result.error
    assert_equal booth, result.booth
    assert_equal @store_a, result.store
  end

  test "他者が配信中でも選択可能で準備作成者の本人配信とはみなさない" do
    create_booth(@store_a)
    booth_b = create_booth(@store_b)
    session = start_broadcast(booth_b, @other, creator: @actor)
    result = resolve(purpose: :select_booth, target_id: booth_b.id)
    assert result.success?
    assert_equal booth_b, result.booth
    assert_nil result.broadcast
    assert result.booth_switchable?
    assert_equal @other.id, session.reload.actual_publisher_user_id
  end

  test "配信終了後は同じ選択を保持し複数なら手動変更できる" do
    booth_a = create_booth(@store_a)
    create_booth(@store_b)
    session = start_broadcast(booth_a, @actor)
    assert_not resolve.booth_switchable?
    session.update!(status: :ended, ended_at: Time.current)
    booth_a.update!(status: :offline, current_stream_session: nil)
    result = resolve(current_booth_id: booth_a.id)
    assert_equal booth_a, result.booth
    assert_nil result.broadcast
    assert result.booth_switchable?
  end

  test "本人の矛盾する配信と権限外の固定先は推測で選択せず変更を保留する" do
    booth = create_booth(@store_a)
    other_booth = create_booth(@store_b)
    start_broadcast(booth, @actor)
    booth.update!(current_stream_session: nil)
    result = resolve(current_booth_id: other_booth.id, purpose: :select_booth, target_id: booth.id)
    assert_equal :broadcast_inconsistent, result.error
    assert_equal other_booth, result.booth
    assert_not result.booth_switchable?

    booth.update!(current_stream_session: booth.stream_sessions.first)
    StoreMembership.where(user: @actor, store: @store_a).delete_all
    result = resolve(current_booth_id: other_booth.id)
    assert_equal :broadcast_inconsistent, result.error
    assert_equal other_booth, result.booth
    assert_nil result.broadcast
  end

  test "管理者は閉鎖済みと非公開店舗を候補に含め選択を維持する" do
    booth_a = create_booth(@store_a)
    closed = create_booth(@store_b, archived_at: Time.current)
    result = resolve(current_booth_id: closed.id)
    assert_equal [ booth_a, closed ], result.booths
    assert_equal closed, result.booth
    assert_equal @store_b, result.store
    assert result.booth_switchable?
    booth_a.update!(archived_at: Time.current)
    assert_equal closed, resolve(current_booth_id: closed.id).booth
  end

  test "管理者の閉鎖済み一件も固定対象でD01の店舗変更例外を維持する" do
    closed = create_booth(@store_a, archived_at: Time.current)
    assert_equal closed, resolve.booth
    assert resolve.booth_fixed?
    assert_nil resolve(current_store_id: @store_b.id).booth
    assert_equal closed, resolve(current_store_id: @store_b.id, purpose: :require_booth).booth
  end

  test "キャストは未閉鎖の担当だけを全店舗から候補にし単独の店舗選択を許可しない" do
    @actor.update!(role: :cast)
    booth_a = create_booth(@store_a)
    booth_b = create_booth(@store_b)
    closed = create_booth(@store_b, archived_at: Time.current)
    [ booth_a, booth_b, closed ].each { |booth| BoothCast.create!(booth: booth, cast_user: @actor) }
    create_booth(@store_a)
    result = resolve(current_store_id: @store_b.id, current_booth_id: closed.id)
    assert_equal [ booth_a, booth_b ], result.booths
    assert_empty result.stores
    assert_nil result.booth
    assert_nil result.store
    assert_equal :not_selectable, resolve(purpose: :select_booth, target_id: closed.id).error
    assert_equal :not_selectable, resolve(purpose: :select_store, target_id: @store_a.id).error
  end

  test "キャストの閉鎖後は残る唯一の担当ブースへ補正する" do
    @actor.update!(role: :cast)
    booth_a = create_booth(@store_a)
    booth_b = create_booth(@store_b)
    [ booth_a, booth_b ].each { |booth| BoothCast.create!(booth: booth, cast_user: @actor) }
    booth_a.update!(archived_at: Time.current)
    result = resolve(current_booth_id: booth_a.id, current_store_id: @store_a.id)
    assert_equal booth_b, result.booth
    assert_equal @store_b, result.store
    assert result.booth_fixed?
  end

  test "システム管理者は所属なしで全店舗の現役と閉鎖済みを選べる" do
    @actor.update!(role: :system_admin)
    StoreMembership.where(user: @actor).delete_all
    booth_a = create_booth(@store_a)
    closed = create_booth(@store_b, archived_at: Time.current)
    result = resolve(purpose: :select_booth, target_id: closed.id)
    assert result.success?
    assert_equal [ booth_a, closed ], result.booths
    assert_equal [ @store_a, @store_b ], result.stores
    assert_equal closed, result.booth
  end

  test "D02 キャスト招待承認成功時は有効なAがあっても新規Bと所属店舗へ切り替える" do
    @actor.update!(role: :cast)
    booth_a = create_booth(@store_a)
    booth_b = create_booth(@store_b)
    [ booth_a, booth_b ].each { |booth| BoothCast.create!(booth: booth, cast_user: @actor) }
    assert_equal booth_a, resolve(current_booth_id: booth_a.id).booth
    result = resolve(current_booth_id: booth_a.id, purpose: :invitation_accepted, target_id: booth_b.id)
    assert result.success?
    assert_equal booth_b, result.booth
    assert_equal @store_b, result.store
    start_broadcast(booth_a, @actor)
    rejected = resolve(current_booth_id: booth_a.id, purpose: :invitation_accepted, target_id: booth_b.id)
    assert_equal :broadcast_fixed, rejected.error
    assert_equal booth_a, rejected.booth
  end

  test "役割変更と退会は古いactorの権限で候補を返さない" do
    booth = create_booth(@store_a)
    stale_actor = User.find(@actor.id)
    @actor.update!(role: :customer)
    result = resolve(actor: stale_actor, current_booth_id: booth.id)
    assert_empty result.booths
    assert_empty result.stores
    assert_nil result.booth
    @actor.update!(role: :store_admin, deleted_at: Time.current)
    assert_empty resolve(actor: stale_actor).booths
  end

  test "店舗一件は未選択や無効IDから固定しブースなしでも管理できる" do
    StoreMembership.where(user: @actor, store: @store_b).delete_all
    result = resolve(current_store_id: @store_b.id)
    assert_nil result.booth
    assert_equal @store_a, result.store
    assert result.store_fixed?
    assert_not result.store_switchable?
  end

  %i[cast store_admin system_admin].each do |role|
    test "#{role}の候補0件 1件 複数で固定と未選択維持を切り替える" do
      @actor.update!(role: role)
      empty = resolve
      assert_nil empty.booth
      assert_not empty.booth_fixed?
      assert_not empty.booth_switchable?

      first = create_booth(@store_a)
      BoothCast.create!(booth: first, cast_user: @actor) if role == :cast
      sole = resolve
      assert_equal first, sole.booth
      assert sole.booth_fixed?
      assert_not sole.booth_switchable?

      second = create_booth(@store_b)
      BoothCast.create!(booth: second, cast_user: @actor) if role == :cast
      multiple = resolve(purpose: :require_booth)
      assert_nil multiple.booth
      assert_not multiple.booth_fixed?
      assert multiple.booth_switchable?
      assert_equal second, resolve(current_booth_id: second.id).booth

      start_broadcast(first, @actor)
      fixed = resolve(current_booth_id: second.id)
      assert_equal first, fixed.booth
      assert fixed.booth_fixed?
      assert_not fixed.booth_switchable?
    end
  end

  private

  def resolve(**options)
    CurrentSelectionService.new(actor: @actor, **options).call
  end

  def create_booth(store, **attributes)
    Booth.create!(store: store, name: "#{store.name} booth", **attributes)
  end

  def start_broadcast(booth, publisher, creator: @other)
    session = StreamSession.create!(booth: booth, store: booth.store, started_by_cast_user: creator,
      status: :live, started_at: 10.minutes.ago, broadcast_started_at: 5.minutes.ago,
      actual_publisher_user: publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current)
    booth.update!(status: :live, current_stream_session: session)
    session
  end
end
