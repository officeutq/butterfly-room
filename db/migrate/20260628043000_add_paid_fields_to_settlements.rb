# frozen_string_literal: true

class AddPaidFieldsToSettlements < ActiveRecord::Migration[8.1]
  def change
    add_column :settlements, :paid_at, :datetime
    add_reference :settlements, :paid_by_user, foreign_key: { to_table: :users }
  end
end
