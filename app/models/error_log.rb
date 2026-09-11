# frozen_string_literal: true

class ErrorLog < ApplicationRecord
  include LogEntry

  # A separate pool to the SAME database keeps errors outside business rollbacks.
  # No foreign keys: the failing transaction may hold locks on the referenced rows.
  establish_connection connection_db_config.configuration_hash.merge(pool: 2, checkout_timeout: 1)

  SEVERITIES = %w[info warning error].freeze

  validates :severity, inclusion: { in: SEVERITIES }
  validates :exception_class, presence: true, length: { maximum: 200 }
  validates :summary, presence: true, length: { maximum: 300 }
  validates :job_class, length: { maximum: 200 }, allow_nil: true
  validates :job_id, length: { maximum: 100 }, allow_nil: true
  validates :executions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :bounded_backtrace

  private

  def bounded_backtrace
    unless backtrace.is_a?(Array) && backtrace.size <= 30 && backtrace.all? { |line| line.is_a?(String) && line.bytesize <= 250 }
      errors.add(:backtrace, :invalid)
    end
  end
end
