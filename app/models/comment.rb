class Comment < ApplicationRecord
  KIND_CHAT = "chat"
  KIND_DRINK = "drink"
  KIND_DRINK_CONSUMED = "drink_consumed"
  KIND_ENTRY = "entry"
  KIND_EXIT = "exit"
  KIND_SYSTEM = "system"

  KINDS = [
    KIND_CHAT,
    KIND_DRINK,
    KIND_DRINK_CONSUMED,
    KIND_ENTRY,
    KIND_EXIT,
    KIND_SYSTEM
  ].freeze

  belongs_to :stream_session
  belongs_to :booth
  belongs_to :user

  has_many :comment_reports, dependent: :restrict_with_error

  scope :alive, -> { where(deleted_at: nil) }

  before_validation :normalize_kind
  before_validation :normalize_body
  before_validation :normalize_metadata

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :body, length: { maximum: 200 }, allow_nil: true
  validates :body, presence: true, if: :chat?

  def chat?
    kind == KIND_CHAT
  end

  def hidden?
    return false unless chat?

    metadata_hash["hidden"] == true || metadata_hash[:hidden] == true
  end

  def hide_by!(user)
    raise ArgumentError, "chat comment only" unless chat?

    update!(
      metadata: metadata_hash.merge(
        "hidden" => true,
        "hidden_at" => Time.current.iso8601,
        "hidden_by_user_id" => user.id
      )
    )
  end

  def unhide!
    raise ArgumentError, "chat comment only" unless chat?

    update!(
      metadata: metadata_hash.merge(
        "hidden" => false,
        "hidden_at" => nil,
        "hidden_by_user_id" => nil
      )
    )
  end

  def metadata_hash
    metadata.is_a?(Hash) ? metadata : {}
  end

  private

  def normalize_kind
    self.kind = kind.to_s.strip.presence || KIND_CHAT
  end

  def normalize_body
    self.body = body.to_s.strip.presence
  end

  def normalize_metadata
    self.metadata =
      case metadata
      when ActionController::Parameters
        metadata.to_unsafe_h
      when Hash
        metadata
      when nil
        {}
      else
        metadata.respond_to?(:to_h) ? metadata.to_h : {}
      end
  rescue TypeError, NoMethodError
    self.metadata = {}
  end
end
