# frozen_string_literal: true

class AddSalesSupportCompanyToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :sales_support_company, :boolean, null: false, default: false
  end
end
