# frozen_string_literal: true

class AddImageEditingSourcesAndCropData < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.jsonb :avatar_crop_data, null: false, default: {}
      t.jsonb :cover_image_crop_data, null: false, default: {}
    end

    add_column :stores, :thumbnail_crop_data, :jsonb, null: false, default: {}
    add_column :booths, :thumbnail_image_crop_data, :jsonb, null: false, default: {}
  end
end
