require "test_helper"

class PublicBoothCardSelectionTest < ActionDispatch::IntegrationTest
  setup do
    @publisher = User.create!(email: "card-publisher@example.test", password: "password", role: :cast)
    @a, @b = %w[A B].map do |name|
      Booth.create!(store: Store.create!(name: "カード店舗#{name}", published: true), name: "カード#{name}",
        ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{name}")
    end
  end

  %i[cast store_admin system_admin].each do |role|
    test "#{role}が選択外Bを開くと状態にかかわらず視聴へ進み選択と配信を変えない" do
      sign_in_role(role)
      %i[offline standby live away].each do |status|
        prepare_b(status) unless status == :offline
        snapshot = Booth.order(:id).pluck(:id, :status, :current_stream_session_id)
        assert_no_difference "StreamSession.count" do
          get enter_booth_path(@b)
          assert_redirected_to booth_path(@b)
          follow_redirect!
          assert_response :success
        end
        assert_equal @a.id, @request.session[:current_booth_id]
        assert_equal @a.store_id, @request.session[:current_store_id]
        assert_equal snapshot, Booth.order(:id).pluck(:id, :status, :current_stream_session_id)
        assert_select "#app_header [data-selection-booth-name]", text: @a.name
        post enter_as_cast_booth_path(@b)
        assert_response :conflict
      end
    end

    test "#{role}の選択中カードは既存の配信入口を維持する" do
      sign_in_role(role)
      with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "false") do
        if role == :cast
          assert_difference "StreamSession.count", 1 do
            get enter_booth_path(@a)
            assert_redirected_to live_cast_booth_path(@a)
          end
        else
          assert_no_difference "StreamSession.count" do
            get enter_booth_path(@a), headers: { "Turbo-Frame" => "modal" }
            assert_response :success
            assert_select "turbo-frame#modal a[href='#{booth_path(@a)}']", text: "視聴する"
            assert_select "turbo-frame#modal form[action='#{enter_as_cast_booth_path(@a)}']"
          end
        end
      end
    end

    test "#{role}の選択外カードは通常遷移し明示的な配信ボタンとは区別する" do
      sign_in_role(role)
      get root_path, params: { mode: "booths" }
      assert_response :success
      assert_select "form[action='#{enter_booth_path(@b)}']"
      assert_select "form[action='#{enter_booth_path(@b)}'][data-turbo-frame='modal']", count: 0
      if role == :cast
        assert_select "#app_footer form[action='#{enter_as_cast_booth_path(@a)}'][method='post']"
        # 別タブで選択が変わっても、古い配信ボタンを視聴へ読み替えない。
        post cast_current_booth_path, params: { booth_id: @b.id, return_to_key: "booth_show" }
        post enter_as_cast_booth_path(@a)
        assert_response :conflict
      elsif role == :store_admin
        assert_select "#app_footer a[href='#{new_admin_cast_invitation_path}']"
      else
        assert_select "#app_footer a[href='#{select_modal_cast_booths_path(return_to_key: 'booth_live')}']"
      end
    end
  end

  test "古い管理者カードがモーダルを要求しても選択外Bの公開画面へ全画面移動する" do
    sign_in_role(:store_admin)
    get enter_booth_path(@b), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "turbo-frame#modal [data-redirect-url='#{booth_path(@b)}']"
    assert_select "form[action='#{enter_as_cast_booth_path(@b)}']", count: 0
    assert_equal @a.id, @request.session[:current_booth_id]
  end

  test "他者が配信している選択中Bも管理者は視聴を選べる" do
    sign_in_role(:store_admin)
    prepare_b(:live)
    post cast_current_booth_path, params: { booth_id: @b.id, return_to_key: "booth_show" }
    get enter_booth_path(@b), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "a[href='#{booth_path(@b)}']", text: "視聴する"
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      post enter_as_cast_booth_path(@b)
      assert_response :conflict
      assert_includes response.body, "このブースはすでに他の人が配信中です"
    end
    assert_equal @publisher.id, @b.reload.current_stream_session.actual_publisher_user_id
  end

  private

  def sign_in_role(role)
    @actor = User.create!(email: "card-#{role}@example.test", password: "password", role: role)
    [ @a, @b ].each do |booth|
      BoothCast.create!(booth: booth, cast_user: @actor) if role == :cast
      StoreMembership.create!(store: booth.store, user: @actor, membership_role: :admin) if role == :store_admin
    end
    sign_in @actor
    post cast_current_booth_path, params: { booth_id: @a.id, return_to_key: "booth_show" }
    assert_redirected_to cast_booth_path(@a)
  end

  def prepare_b(status)
    stream = StreamSession.create!(store: @b.store, booth: @b, started_by_cast_user: @publisher,
      status: :live, started_at: Time.current, ivs_stage_arn: @b.ivs_stage_arn)
    if %i[live away].include?(status)
      stream.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
        actual_publisher_recorded_at: Time.current, broadcast_started_at: Time.current)
    end
    @b.update!(current_stream_session: stream, status: status)
  end
end
