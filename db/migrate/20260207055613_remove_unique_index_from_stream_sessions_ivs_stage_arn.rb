class RemoveUniqueIndexFromStreamSessionsIvsStageArn < ActiveRecord::Migration[8.1]
  def change
    # schema.rb にあるこのindexを外す
    # t.index ["ivs_stage_arn"], name: "index_stream_sessions_on_ivs_stage_arn", unique: true, where: "(ivs_stage_arn IS NOT NULL)"

    remove_index :stream_sessions, name: "index_stream_sessions_on_ivs_stage_arn"

    # 代替：検索用に通常indexを貼り直す（任意）
    add_index :stream_sessions, :ivs_stage_arn
  end
end
