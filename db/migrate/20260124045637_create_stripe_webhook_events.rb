class CreateStripeWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_webhook_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.datetime :received_at, null: false
      t.jsonb :payload
      t.string :livemode
      t.timestamps
    end

    add_index :stripe_webhook_events, :event_id, unique: true
  end
end
