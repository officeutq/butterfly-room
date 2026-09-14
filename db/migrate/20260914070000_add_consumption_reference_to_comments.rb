class AddConsumptionReferenceToComments < ActiveRecord::Migration[8.1]
  def up
    add_reference :comments, :drink_order, foreign_key: true, index: { unique: true, where: "drink_order_id IS NOT NULL" }
    add_check_constraint :comments,
      "user_id IS NOT NULL OR COALESCE(kind = 'drink_consumed' AND metadata @> '{\"publisher_unknown\": true}'::jsonb, false)",
      name: "comments_user_or_unknown_consumption"
    change_column_null :comments, :user_id, true
  end

  def down
    # 不明通知を削除・別人へ補完せず、データがある場合は明示的に差し戻しを止める。
    change_column_null :comments, :user_id, false
    remove_check_constraint :comments, name: "comments_user_or_unknown_consumption"
    remove_reference :comments, :drink_order, foreign_key: true
  end
end
