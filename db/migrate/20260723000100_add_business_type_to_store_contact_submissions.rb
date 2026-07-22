# frozen_string_literal: true

class AddBusinessTypeToStoreContactSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :store_contact_submissions, :business_type, :string, limit: 120
  end
end
