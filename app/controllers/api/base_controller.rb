module Api
  class BaseController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :authenticate_api_user!

    rescue_from ActiveRecord::RecordNotFound,        with: -> { render_error("not_found", :not_found) }
    rescue_from ActionController::ParameterMissing,  with: ->(e) { render_error(e.message, :bad_request) }
    rescue_from Pundit::NotAuthorizedError,          with: -> { render_error("forbidden", :forbidden) }

    protected

    attr_reader :current_user

    # Accepts either a Devise session cookie OR an Authorization: Bearer token.
    # Bearer tokens are resolved against User#api_token (a hypothetical future
    # column) — for now we fall through to Devise warden for session auth.
    def authenticate_api_user!
      if request.headers["Authorization"].to_s.start_with?("Bearer ")
        token = request.headers["Authorization"].split(" ", 2).last
        @current_user = User.find_by(api_token: token) if User.column_names.include?("api_token")
      end

      @current_user ||= warden.user(:user)
      render_error("unauthorized", :unauthorized) unless @current_user
    end

    def render_error(message, status)
      render json: { error: message }, status: status
    end
  end
end
