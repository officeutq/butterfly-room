class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  enum :role, { customer: 0, cast: 1, store_admin: 2, system_admin: 3 }

  ROLE_LEVELS = {
    customer: 0,
    cast: 1,
    store_admin: 2,
    system_admin: 3
  }.freeze

  has_one :wallet, foreign_key: :customer_user_id, dependent: :destroy, inverse_of: :customer_user
  has_many :store_memberships, dependent: :destroy
  has_many :stores, through: :store_memberships
  has_many :favorite_booths, dependent: :destroy
  has_many :favorite_stores, dependent: :destroy

  # --- Soft delete ---
  def deleted?
    deleted_at.present?
  end

  # Devise: 停止ユーザーはログイン不可
  def active_for_authentication?
    super && !deleted?
  end

  def role_level
    ROLE_LEVELS.fetch(role.to_sym)
  rescue KeyError, NoMethodError
    -1
  end

  def at_least?(required_role)
    required_level = ROLE_LEVELS.fetch(required_role.to_sym)
    role_level >= required_level
  rescue KeyError
    false
  end

  def admin_of_store?(store_id)
    return false if store_id.blank?
    store_memberships.admin_only.exists?(store_id: store_id)
  end
end
