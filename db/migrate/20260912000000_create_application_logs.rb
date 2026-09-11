class CreateApplicationLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :error_logs do |t|
      common_columns(t)
      t.string :severity, limit: 10, null: false
      t.boolean :handled, null: false, default: false
      t.string :exception_class, limit: 200, null: false
      t.text :summary, null: false
      t.jsonb :backtrace, null: false, default: []
      t.string :job_class, limit: 200
      t.string :job_id, limit: 100
      t.integer :executions
    end

    create_table :change_logs do |t|
      common_columns(t)
      t.string :target_type, limit: 50, null: false
      t.bigint :target_id, null: false
      t.string :action, limit: 20, null: false
      t.jsonb :change_data, null: false, default: {}
    end

    %i[error_logs change_logs].each do |table|
      add_index table, [ :occurred_at, :id ]
      add_index table, [ :actor_user_id, :occurred_at, :id ]
      add_index table, [ :store_id, :occurred_at, :id ]
      add_index table, :request_id
      add_index table, [ :archived_at, :occurred_at, :id ]
    end
    add_index :error_logs, [ :severity, :occurred_at, :id ]
    add_index :change_logs, [ :target_type, :target_id, :occurred_at, :id ], name: :index_change_logs_on_target_and_time
    add_check_constraint :error_logs, "severity IN ('info', 'warning', 'error')", name: :error_logs_severity
    add_check_constraint :change_logs, "action IN ('created', 'updated')", name: :change_logs_action
    add_check_constraint :change_logs, "jsonb_typeof(change_data) = 'object' AND octet_length(change_data::text) <= 16384", name: :change_logs_data_size
  end

  private

  def common_columns(table)
    table.datetime :occurred_at, null: false
    table.datetime :created_at, null: false
    table.datetime :archived_at
    table.bigint :actor_user_id
    table.bigint :store_id
    table.bigint :stream_session_id
    table.string :source, limit: 20, null: false
    table.string :request_id, limit: 100
    # Identifiers survive target deletion; error writes must not lock business rows.
  end
end
