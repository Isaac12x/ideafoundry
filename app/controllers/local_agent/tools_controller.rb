module LocalAgent
  class ToolsController < ActionController::API
    before_action :require_local_request
    before_action :set_user

    def create
      result = Toolbox.new(user: @user, agent_run: agent_run).call(params[:tool_name], tool_arguments)
      render json: result, status: result[:ok] ? :ok : :unprocessable_content
    end

    private

    def require_local_request
      return if request.local? || Rails.env.development? || Rails.env.test?

      render json: { ok: false, error: "forbidden", details: "Local agent tools only accept local requests." }, status: :forbidden
    end

    def set_user
      @user = User.first || User.create!(email: "user@example.com", name: "Default User")
    end

    def agent_run
      return if params[:agent_run_id].blank?

      @user.agent_runs.find_by(id: params[:agent_run_id])
    end

    def tool_arguments
      raw = params[:arguments].presence || params.except(:controller, :action, :tool_name, :agent_run_id)
      raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h
    end
  end
end
