class AddOnboardingFieldsToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :onboarding_step, :integer
    add_column :stores, :onboarding_invite_copied_at, :datetime

    add_index :stores, :onboarding_step
    add_index :stores, :onboarding_invite_copied_at
  end
end
