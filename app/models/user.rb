class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  enum :role, { customer: 0, cast: 1, store_admin: 2, system_admin: 3 }
end
