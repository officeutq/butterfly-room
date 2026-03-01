class BoothCast < ApplicationRecord
  belongs_to :booth
  belongs_to :cast_user, class_name: "User"

  validates :booth_id, presence: true
  validates :cast_user_id, presence: true

  # Phase1: 1ブース1キャスト固定（差し替え禁止）
  validates :booth_id,
            uniqueness: {
              message: "には既にキャストが紐づいています（Phase1では変更できません。変更が必要な場合は新規ブース作成＋旧ブースアーカイブで対応してください）"
            }
end
