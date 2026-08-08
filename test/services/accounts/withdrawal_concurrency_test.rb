# frozen_string_literal: true

require "test_helper"
require "timeout"

class Accounts::WithdrawalConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(6)
    @store = Store.create!(name: "Concurrent Withdrawal #{suffix}", published: true)
    @admins = 2.times.map do |index|
      User.create!(
        email: "withdrawal-concurrent-#{suffix}-#{index}@example.com",
        password: "password",
        password_confirmation: "password",
        role: :store_admin
      ).tap do |admin|
        StoreMembership.create!(store: @store, user: admin, membership_role: :admin)
      end
    end
  end

  teardown do
    StoreMembership.where(store_id: @store&.id).delete_all
    User.where(id: @admins&.map(&:id)).delete_all
    Store.where(id: @store&.id).delete_all
  end

  test "concurrent last administrators do not leave a published store" do
    ready = Queue.new
    release = Queue.new

    synchronized_service = Class.new(Accounts::WithdrawalService) do
      define_method(:locked_admin_stores) do |user|
        ready << user.id
        release.pop
        super(user)
      end
    end

    threads = @admins.map do |admin|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          synchronized_service.new(user: User.find(admin.id)).call!
        end
      end
    end

    2.times { Timeout.timeout(5) { ready.pop } }
    2.times { release << true }
    threads.each { |thread| Timeout.timeout(10) { thread.value } }

    assert @admins.all? { |admin| admin.reload.deleted? }
    assert_not @store.reload.published?
  ensure
    2.times { release << true } if release
    threads&.each do |thread|
      thread.join(1)
      next unless thread.alive?

      thread.kill
      thread.join
    end
  end
end
