# frozen_string_literal: true

class RestrictUserIdentityUniquenessToActiveUsers < ActiveRecord::Migration[8.1]
  def up
    assert_no_active_duplicates!(:email)
    assert_no_active_duplicates!(:phone_number)

    remove_index :users, name: "index_users_on_email"
    remove_index :users, name: "index_users_on_phone_number"

    add_index :users,
              :email,
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_users_on_email"
    add_index :users,
              :phone_number,
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_users_on_phone_number"
  end

  def down
    remove_index :users, name: "index_users_on_email"
    remove_index :users, name: "index_users_on_phone_number"

    add_index :users, :email, unique: true, name: "index_users_on_email"
    add_index :users, :phone_number, unique: true, name: "index_users_on_phone_number"
  end

  private

  def assert_no_active_duplicates!(column)
    quoted_column = connection.quote_column_name(column)
    duplicate_value = select_value(<<~SQL.squish)
      SELECT #{quoted_column}
      FROM users
      WHERE deleted_at IS NULL
        AND #{quoted_column} IS NOT NULL
      GROUP BY #{quoted_column}
      HAVING COUNT(*) > 1
      LIMIT 1
    SQL

    return if duplicate_value.nil?

    raise ActiveRecord::MigrationError,
          "users.#{column} has duplicate values among active users"
  end
end
