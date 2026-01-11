class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def require_role!(*roles)
    authenticate_user! # Devise

    role = current_user.role.to_sym
    return if roles.include?(role)

    head :forbidden
  end

  def authorize!(policy_class, record, action)
    policy = policy_class.new(current_user, record)
    head(:forbidden) unless policy.public_send("#{action}?")
  end
end
