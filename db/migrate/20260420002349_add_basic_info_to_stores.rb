class AddBasicInfoToStores < ActiveRecord::Migration[8.1]
  def change
    change_table :stores, bulk: true do |t|
      # 基本情報
      t.string :address
      t.string :phone_number
      t.string :business_hours
      t.string :website_url

      # SNS
      t.string :x_url
      t.string :instagram_url
      t.string :tiktok_url
      t.string :youtube_url

      # Geocoding
      t.float :latitude
      t.float :longitude
    end
  end
end
