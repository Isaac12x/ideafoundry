module LocalAgent
  class ToolsController < ActionController::API
    before_action :require_local_request
    before_action :set_user

    def index
      if request.post? && root_tool_name.present?
        run_tool(root_tool_name, root_tool_arguments)
      else
        render json: {
          ok: true,
          tools: Toolbox.tool_definitions,
          tool_names: Toolbox.supported_tool_names,
          invocation: {
            method: "POST",
            path: "/local-agent/tools/:tool_name",
            root_path: "/local-agent/tools",
            root_payload_keys: %w[tool_name name arguments]
          }
        }
      end
    end

    def create
      run_tool(params[:tool_name], tool_arguments)
    end

    private

    def run_tool(tool_name, arguments)
      result = Toolbox.new(user: @user, agent_run: agent_run).call(tool_name, arguments)
      render json: result, status: result[:ok] ? :ok : :unprocessable_content
    end

    def require_local_request
      return if request.local? || Rails.env.development? || Rails.env.test?

      render json: { ok: false, error: "forbidden", details: "Local agent tools only accept local requests." }, status: :forbidden
    end

    def set_user
      @user = User.first || User.create!(email: "user@example.com", name: "Default User")
    end

    def agent_run
      # The Python runner sends the run id as a header; accept the param too.
      run_id = params[:agent_run_id].presence ||
               request.headers["X-Idea-Foundry-Agent-Run-Id"].presence
      return if run_id.blank?

      @user.agent_runs.find_by(id: run_id)
    end

    def root_tool_name
      params[:tool_name].presence || params[:name].presence || params.dig(:tool, :name).presence
    end

    def root_tool_arguments
      raw = params[:arguments].presence || params[:input].presence || params[:params].presence ||
            params.except(:controller, :action, :tool_name, :name, :tool, :agent_run_id)
      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    end

    def tool_arguments
      raw = params[:arguments].presence || params.except(:controller, :action, :tool_name, :agent_run_id)
      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    end
  end
end
