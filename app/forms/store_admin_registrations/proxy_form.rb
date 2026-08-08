# frozen_string_literal: true

module StoreAdminRegistrations
  class ProxyForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :display_name, :string
    attribute :email, :string

    attr_accessor :store, :actor
    attr_reader :result

    validates :display_name, presence: true
    validates :email, presence: true
    validate :existing_user_must_be_eligible

    def save
      return false unless valid?

      @result = StoreAdminRegistrations::RegisterProxy.call!(
        store: store,
        actor: actor,
        display_name: display_name,
        email: normalized_email
      )
      true
    rescue StoreAdminRegistrations::RegisterProxy::NotAuthorized
      errors.add(:base, "店舗責任者を登録代行する権限がありません")
      false
    rescue StoreAdminRegistrations::RegisterProxy::InvalidExistingRole
      errors.add(:email, "は店舗管理者以外のアカウントとして使用されています。別のメールアドレスを指定するか、運営へお問い合わせください")
      false
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.each do |error|
        errors.add(error.attribute, error.type, **error.options.except(:message))
      end
      false
    end

    private

    def normalized_email
      email.to_s.strip.downcase
    end

    def existing_user_must_be_eligible
      return if email.blank?

      user = User.active.find_by(email: normalized_email)
      return if user.blank?

      unless user.store_admin?
        errors.add(:email, "は店舗管理者以外のアカウントとして使用されています。別のメールアドレスを指定するか、運営へお問い合わせください")
      end
    end
  end
end
