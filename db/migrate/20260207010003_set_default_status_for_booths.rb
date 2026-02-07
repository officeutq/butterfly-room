class SetDefaultStatusForBooths < ActiveRecord::Migration[8.1]
  def change
    change_column_default :booths, :status, from: nil, to: 0
  end
end
