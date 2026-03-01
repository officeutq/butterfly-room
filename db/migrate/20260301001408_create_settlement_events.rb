class CreateSettlementEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :settlement_events do |t|
      t.references :settlement, null: false, foreign_key: true
      t.references :actor_user, null: false, foreign_key: { to_table: :users }
      t.integer :action, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :settlement_events, :action
    add_index :settlement_events, :created_at
  end
end
