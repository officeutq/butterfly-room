class AddIvsStageArnToBooths < ActiveRecord::Migration[8.1]
  def change
    add_column :booths, :ivs_stage_arn, :string
    add_index  :booths, :ivs_stage_arn
  end
end
