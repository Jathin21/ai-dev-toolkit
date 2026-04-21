class ApplicationController < ActionController::Base
  include Pundit::Authorization

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up,         keys: [:name])
    devise_parameter_sanitizer.permit(:account_update,  keys: [:name, :encrypted_github_token])
  end

  def forbidden
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "You don't have access to that." }
      format.json { render json: { error: "forbidden" }, status: :forbidden }
    end
  end
end
