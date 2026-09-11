# frozen_string_literal: true

require "test_helper"

class Logs::RecordingTest < ActiveSupport::TestCase
  # Exercise real commits and two independent pools, not fixture transactions.
  self.use_transactional_tests = false

  setup do
    @request_id = SecureRandom.uuid
    @store = Store.create!(name: "変更前")
  end

  teardown do
    ErrorLog.where(request_id: @request_id).delete_all
    ChangeLog.where(store_id: @store.id).delete_all
    Store.where(id: @store.id).delete_all
  end

  test "writes a change with its business transaction and filters private fields" do
    entry = nil
    @store.transaction do
      @store.update!(name: "変更後", description: "secret-token@example.com")
      entry = Logs::RecordChangeService.call(
        record: @store, changes: @store.saved_changes.merge("password" => [ nil, "password-secret" ]),
        actor_user: User.new(id: 123), source: "web", request_id: @request_id
      )
    end
    assert_equal({ "name" => [ "変更前", "変更後" ], "description" => [ nil, "[FILTERED]" ] }, entry.change_data)
    assert_equal "Store", entry.target_type
    assert_equal @store.id, entry.target_id
    assert_equal 123, entry.actor_user_id
    assert_equal @request_id, entry.request_id
    assert_not_includes entry.to_json, "password-secret"
    assert_not_includes entry.to_json, "secret-token@example.com"
  end

  test "requires a business transaction" do
    assert_raises(ArgumentError) { record_change }
  end

  test "outer rollback removes both business update and change log" do
    assert_no_difference "ChangeLog.count" do
      @store.transaction do
        @store.update!(name: "取り消される")
        @store.transaction(requires_new: true) { record_change }
        raise ActiveRecord::Rollback
      end
    end
    assert_equal "変更前", @store.reload.name
  end

  test "required log failure rolls back the update" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @store.transaction do
        @store.update!(name: "取り消される")
        Logs::RecordChangeService.call(record: @store, changes: @store.saved_changes, source: "invalid")
      end
    end
    assert_equal "変更前", @store.reload.name
  end

  test "unchanged values and fields outside the allowlist do not produce logs" do
    @store.transaction do
      assert_nil Logs::RecordChangeService.call(record: @store, changes: { "name" => [ "same", "same" ], "updated_at" => [ nil, Time.current ] })
    end
    assert_not ChangeLog.where(store_id: @store.id).exists?
  end

  test "image differences keep only blob identifiers" do
    @store.transaction do
      entry = Logs::RecordChangeService.call(record: @store, changes: {
        "thumbnail" => [ nil, { "source_blob_id" => 12, "display_blob_id" => 13, "signed_url" => "secret-url" } ]
      })
      assert_equal [ nil, { "source_blob_id" => 12, "display_blob_id" => 13 } ], entry.change_data["thumbnail"]
    end
  end

  test "log bodies cannot be updated or destroyed through model persistence" do
    entry = @store.transaction { record_change }
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(action: "created") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
  end

  test "errors survive business rollback and do not use the business connection" do
    assert_not_equal ErrorLog.connection_pool, ApplicationRecord.connection_pool
    @store.transaction do
      @store.update!(name: "取り消される")
      @store.transaction(requires_new: true) do
        error_entry
        raise ActiveRecord::Rollback
      end
      raise ActiveRecord::Rollback
    end
    assert_equal "変更前", @store.reload.name
    assert_equal 1, ErrorLog.where(request_id: @request_id).count
  end

  test "errors can be recorded while the business connection is in an aborted transaction" do
    @store.transaction do
      begin
        Store.connection.execute("SELECT 1/0")
      rescue ActiveRecord::StatementInvalid => error
        Logs::RecordErrorService.call(error:, context: { request_id: @request_id })
      end
      raise ActiveRecord::Rollback
    end
    assert_equal 1, ErrorLog.where(request_id: @request_id).count
  end

  test "error messages payloads and method arguments are not persisted" do
    error = RuntimeError.new("password=secret email=person@example.com token=access-key")
    error.set_backtrace([ "#{Rails.root}/app/services/stores/update_service.rb:29:in `secret'", "https://secret.example/key:1", "/usr/local/secret.rb:1" ])
    entry = error_entry(error:, context: { password: "secret", payload: { token: "access-key" }, job_class: "ExampleJob", job_id: "job-id", executions: 2 })
    assert_equal [ "app/services/stores/update_service.rb:29" ], entry.backtrace
    assert_equal "ExampleJob", entry.job_class
    assert_equal 2, entry.executions
    assert_not_includes entry.to_json, "access-key"
    assert_not_includes entry.to_json, "person@example.com"
    assert_not_includes entry.to_json, "secret"
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
  end

  test "storage failures use safe fallback and release recursion guard" do
    messages = []
    logger = Object.new
    logger.define_singleton_method(:error) { |value| messages << value }
    with_error_storage_failure do
      assert_nil error_entry(error: RuntimeError.new("application-secret"), logger:)
    end
    assert_equal 1, messages.size
    assert_includes messages.first, "error_log_write_failed"
    assert_not_includes messages.first, "database-password"
    assert_not_includes messages.first, "application-secret"
    assert error_entry
  end

  test "logging failures do not recursively invoke error storage" do
    logger = Object.new
    logger.define_singleton_method(:error) { |_| raise "logger unavailable" }
    with_error_storage_failure do
      assert_nil error_entry(logger:)
    end
    assert_nil ActiveSupport::IsolatedExecutionState[Logs::RecordErrorService::GUARD_KEY]
  end

  test "malformed data and unsupported targets are rejected" do
    entry = ChangeLog.new(target_type: "Store", target_id: @store.id, source: "application", action: "updated", occurred_at: Time.current, change_data: { name: "invalid" })
    assert_not entry.valid?
    assert_raises(ArgumentError) { Logs::RecordChangeService.call(record: User.new, changes: {}) }
  end

  private

  def with_error_storage_failure
    original = ErrorLog.method(:create!)
    ErrorLog.define_singleton_method(:create!) { |*| raise ActiveRecord::ConnectionNotEstablished, "database-password" }
    yield
  ensure
    ErrorLog.define_singleton_method(:create!, original)
  end

  def record_change
    Logs::RecordChangeService.call(record: @store, changes: { "name" => [ "変更前", "変更後" ] }, request_id: @request_id)
  end

  def error_entry(error: RuntimeError.new("example"), context: {}, **options)
    Logs::RecordErrorService.call(error:, context: context.merge(request_id: @request_id), **options)
  end
end
