class StoreBan < ApplicationRecord
  belongs_to :store
  belongs_to :customer_user, class_name: "User"
  belongs_to :created_by_store_admin_user, class_name: "User"
  belongs_to :source_comment, class_name: "Comment", optional: true
  belongs_to :revoked_by_user, class_name: "User", optional: true

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  validates :customer_user_id,
            uniqueness: {
              scope: :store_id,
              conditions: -> { where(revoked_at: nil) }
            },
            if: :active?

  validate :customer_user_must_be_customer

  def active?
    revoked_at.blank?
  end

  def revoked?
    revoked_at.present?
  end

  private

  def customer_user_must_be_customer
    return if customer_user.blank?
    return if customer_user.customer?

    errors.add(:customer_user, "はcustomerのみ指定できます")
  end
end
