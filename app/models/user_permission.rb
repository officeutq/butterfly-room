# frozen_string_literal: true

class UserPermission < ApplicationRecord
  PERMISSION_DEFINITIONS = {
    "store_registration_proxy" => {
      label: "店舗責任者の登録代行",
      allowed_roles: %w[store_admin].freeze
    }.freeze
  }.freeze

  attr_accessor :user_email

  belongs_to :user

  validates :permission_type,
            presence: true,
            inclusion: { in: PERMISSION_DEFINITIONS.keys },
            uniqueness: { scope: :user_id }
  validate :user_role_must_be_allowed
  validate :user_must_be_active

  def self.definition_for(permission_type)
    PERMISSION_DEFINITIONS[permission_type.to_s]
  end

  def self.select_options
    PERMISSION_DEFINITIONS.map { |type, definition| [ definition.fetch(:label), type ] }
  end

  def label
    self.class.definition_for(permission_type)&.fetch(:label, permission_type)
  end

  private

  def user_role_must_be_allowed
    return if user.blank? || permission_type.blank?

    definition = self.class.definition_for(permission_type)
    return if definition.blank?
    return if definition.fetch(:allowed_roles).include?(user.role)

    errors.add(:user, "のロールにはこの追加権限を付与できません")
  end

  def user_must_be_active
    return if user.blank? || !user.deleted?

    errors.add(:user, "は停止中のため追加権限を付与できません")
  end
end
