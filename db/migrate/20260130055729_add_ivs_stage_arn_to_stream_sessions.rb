class AddIvsStageArnToStreamSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :stream_sessions, :ivs_stage_arn, :string

    # Stage ARN は重複させない（1 stream_session = 1 stage の土台）
    add_index :stream_sessions,
              :ivs_stage_arn,
              unique: true,
              where: "ivs_stage_arn IS NOT NULL"
  end
end
