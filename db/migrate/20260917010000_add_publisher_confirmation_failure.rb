class AddPublisherConfirmationFailure < ActiveRecord::Migration[8.1]
  def change
    add_column :stream_publisher_connections, :confirmation_failure_reported_at, :datetime
  end
end
