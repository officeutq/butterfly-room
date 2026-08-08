class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable

  enum :role, { customer: 0, cast: 1, store_admin: 2, system_admin: 3 }

  validates :email, presence: true
  validates :email,
            uniqueness: {
              case_sensitive: true,
              conditions: -> { where(deleted_at: nil) }
            },
            allow_blank: true,
            if: :active_email_changed?
  validates :email,
            format: { with: Devise.email_regexp },
            allow_blank: true,
            if: :devise_will_save_change_to_email?
  validates :password, presence: true, if: :password_required?
  validates :password, confirmation: true, if: :password_required?
  validates :password, length: { within: Devise.password_length }, allow_blank: true
  validates :bio, length: { maximum: 500 }, allow_nil: true
  validates :phone_number,
            uniqueness: { conditions: -> { where(deleted_at: nil) } },
            allow_nil: true,
            if: -> { deleted_at.nil? }

  scope :active, -> { where(deleted_at: nil) }

  ROLE_LEVELS = {
    customer: 0,
    cast: 1,
    store_admin: 2,
    system_admin: 3
  }.freeze

  has_one_attached :avatar

  has_one :wallet, foreign_key: :customer_user_id, dependent: :destroy, inverse_of: :customer_user
  has_many :store_memberships, dependent: :destroy
  has_many :stores, through: :store_memberships
  has_many :booth_casts, foreign_key: :cast_user_id, dependent: :restrict_with_error
  has_many :cast_booths, through: :booth_casts, source: :booth
  has_many :favorite_booths, dependent: :destroy
  has_many :favorite_stores, dependent: :destroy
  has_many :favorite_users, dependent: :destroy
  has_many :favorited_users, through: :favorite_users, source: :target_user
  has_many :created_notifications,
    class_name: "Notification",
    foreign_key: :created_by_user_id,
    dependent: :restrict_with_error
  has_many :received_notifications,
    class_name: "Notification",
    foreign_key: :recipient_user_id,
    dependent: :restrict_with_error
  has_many :notification_reads, dependent: :destroy
  has_many :support_inquiries, dependent: :restrict_with_error
  has_many :sent_support_inquiry_messages,
    class_name: "SupportInquiryMessage",
    foreign_key: :sender_user_id,
    dependent: :restrict_with_error

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

  def store_registration_proxy_allowed?
    return false if deleted? || !store_admin?

    store_memberships
      .admin_only
      .joins(:store)
      .where(stores: { sales_support_company: true })
      .exists?
  end

  def phone_verified?
    phone_number.present? && phone_verified_at.present?
  end

  def unread_notifications_exists?
    Notification.visible_to(self)
                .where.not(id: notification_reads.select(:notification_id))
                .exists?
  end

  class << self
    def find_for_database_authentication(conditions)
      sanitized = devise_parameter_filter.filter(conditions)

      # 有効な再登録アカウントを優先する。退会済みレコードだけの場合は
      # active_for_authentication? で停止理由を返すため、そのレコードを渡す。
      active.find_by(sanitized) || where(sanitized).where.not(deleted_at: nil).first
    end

    def find_first_by_auth_conditions(tainted_conditions, opts = {})
      super(tainted_conditions, opts.merge(deleted_at: nil))
    end

    def with_reset_password_token(token)
      digest = Devise.token_generator.digest(self, :reset_password_token, token)
      active.find_by(reset_password_token: digest)
    end
  end

  protected

  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end

  def active_email_changed?
    deleted_at.nil? && devise_will_save_change_to_email?
  end
end
