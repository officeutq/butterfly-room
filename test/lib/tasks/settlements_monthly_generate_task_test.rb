# frozen_string_literal: true

require "test_helper"
require "rake"

class SettlementsMonthlyGenerateTaskTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  TASK_NAME = "settlements:monthly_generate"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    Rake::Task[TASK_NAME].reenable
    @store = Store.create!(name: "Monthly Task Store #{SecureRandom.hex(4)}")
  end

  teardown do
    travel_back
  end

  test "without argument generates the previous JST month and logs counts" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        create_ledger_entry(points: 20_000, occurred_at: Time.zone.parse("2026-03-05 12:00"))

        out, = capture_io do
          assert_difference -> { Settlement.where(store: @store, kind: :monthly, status: :draft).count }, 1 do
            assert_no_difference -> { SettlementEvent.created.count } do
              Rake::Task[TASK_NAME].invoke
            end
          end
        end

        assert_includes out, "[MonthlySettlement] target=2026-03-01..2026-04-01 created=1 carryover=0 skipped=0"

        settlement = Settlement.where(store: @store, kind: :monthly, status: :draft).order(:id).last
        assert_equal Time.zone.parse("2026-03-01 00:00"), settlement.period_from
        assert_equal Time.zone.parse("2026-04-01 00:00"), settlement.period_to
      end
    end
  end

  test "with YYYY-MM argument generates the specified JST month" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 7, 15, 12, 0, 0) do
        create_ledger_entry(points: 20_000, occurred_at: Time.zone.parse("2026-05-20 12:00"))

        out, = capture_io do
          Rake::Task[TASK_NAME].invoke("2026-05")
        end

        assert_includes out, "[MonthlySettlement] target=2026-05-01..2026-06-01 created=1 carryover=0 skipped=0"
        assert_equal 1, Settlement.where(
          store: @store,
          kind: :monthly,
          period_from: Time.zone.parse("2026-05-01 00:00"),
          period_to: Time.zone.parse("2026-06-01 00:00")
        ).count
      end
    end
  end

  test "below minimum payout is logged as carryover and second run is skipped" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        create_ledger_entry(points: 9_000, occurred_at: Time.zone.parse("2026-03-05 12:00"))

        out, = capture_io do
          assert_no_difference -> { Settlement.count } do
            assert_difference -> { SettlementCarryover.where(store: @store, reason: :min_payout_carryover).count }, 1 do
              Rake::Task[TASK_NAME].invoke
            end
          end
        end

        assert_includes out, "[MonthlySettlement] target=2026-03-01..2026-04-01 created=0 carryover=1 skipped=0"
        assert_includes out, "carryover_detail store_id=#{@store.id} reason=below_min_payout"

        Rake::Task[TASK_NAME].reenable

        out2, = capture_io do
          assert_no_difference -> { Settlement.count } do
            assert_no_difference -> { SettlementCarryover.count } do
              Rake::Task[TASK_NAME].invoke
            end
          end
        end

        assert_includes out2, "[MonthlySettlement] target=2026-03-01..2026-04-01 created=0 carryover=0 skipped=1"
        assert_includes out2, "skipped_detail store_id=#{@store.id} reason=already_processed_below_min_payout"
      end
    end
  end

  test "invalid target month exits with a clear message" do
    _, err = capture_io do
      assert_raises SystemExit do
        Rake::Task[TASK_NAME].invoke("2026-13")
      end
    end

    assert_includes err, "[MonthlySettlement] invalid target_month=\"2026-13\"; expected YYYY-MM"
  end

  test "systemd templates keep the production schedule and docker compose command" do
    service = Rails.root.join("ops/systemd/butterflyve-monthly-settlement.service").read
    timer = Rails.root.join("ops/systemd/butterflyve-monthly-settlement.timer").read

    assert_includes service, "WorkingDirectory=/home/ec2-user/apps/butterfly-room"
    assert_includes service, "--env-file /home/ec2-user/apps/butterfly-room/.env.production"
    assert_includes service, "exec -T app bin/rails settlements:monthly_generate"
    assert_includes service, "TimeoutStartSec=600"

    assert_includes timer, "OnCalendar=*-*-01 04:00"
    assert_includes timer, "JST 13:00 = UTC 04:00"
    assert_includes timer, "Persistent=true"
    assert_not_includes timer, "RandomizedDelaySec"
  end

  private

  def create_ledger_entry(points:, occurred_at:)
    booth = Booth.create!(store: @store, name: "Monthly Task Booth #{SecureRandom.hex(4)}", status: :offline)
    cast = User.create!(email: "monthly-task-cast-#{SecureRandom.hex(4)}@example.com", password: "password", role: :cast)
    stream_session = StreamSession.create!(store: @store, booth: booth, status: :live, started_at: occurred_at, started_by_cast_user: cast)
    customer = User.create!(email: "monthly-task-customer-#{SecureRandom.hex(4)}@example.com", password: "password", role: :customer)
    item = DrinkItem.create!(store: @store, name: "Monthly Task Drink #{SecureRandom.hex(4)}", price_points: points, position: 0, enabled: true)
    order = DrinkOrder.create!(store: @store, booth: booth, stream_session: stream_session, customer_user: customer, drink_item: item, status: :consumed)

    StoreLedgerEntry.create!(
      store: @store,
      stream_session: stream_session,
      drink_order: order,
      points: points,
      occurred_at: occurred_at
    )
  end
end
