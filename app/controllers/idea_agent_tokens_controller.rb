class IdeaAgentTokensController < ApplicationController
  before_action :set_idea
  before_action :require_idea_work_tokens_enabled, only: [:create, :skill]

  def create
    token = nil

    @idea.transaction do
      @idea.idea_agent_tokens.destroy_all
      token = IdeaAgentToken.generate(idea: @idea, name: "Idea agent")
    end

    flash[:idea_agent_token] = token.raw_token
    flash[:idea_agent_token_idea_id] = @idea.id

    redirect_to @idea, notice: "Agent token created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @idea, alert: "Failed to create agent token: #{e.record.errors.full_messages.to_sentence}"
  end

  def destroy
    @idea.idea_agent_tokens.destroy_all

    redirect_to @idea, notice: "Agent token revoked."
  end

  def skill
    send_data agent_skill_markdown,
              filename: "idea-#{@idea.id}-agent-skill.md",
              type: "text/markdown; charset=utf-8",
              disposition: "attachment"
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def require_idea_work_tokens_enabled
    return if @user.idea_work_tokens_enabled?

    redirect_to @idea, alert: "Idea work tokens are disabled in settings."
  end

  def agent_skill_markdown
    base_url = request.base_url
    document_path = api_v1_idea_document_path(@idea)
    idea_title = @idea.title.to_s.squish
    metadata = { idea_id: @idea.id, api_base: "#{base_url}/api/v1" }.to_json

    <<~MARKDOWN
      ---
      name: idea-foundry-idea-work
      version: 1.0.0
      description: Work on one Idea Foundry idea document through a scoped access token.
      homepage: #{base_url}
      metadata: #{metadata}
      ---

      # Idea Foundry Idea Work

      You have access to one Idea Foundry idea: "#{idea_title}".

      ## Authentication

      Use the idea work token from the human as a bearer token. Send it only to #{base_url}.

      ```bash
      export IDEA_FOUNDRY_TOKEN="paste-token-here"
      ```

      ## Read the Idea

      Endpoint: `GET #{document_path}`

      ```bash
      curl #{base_url}#{document_path} \\
        -H "Authorization: Bearer $IDEA_FOUNDRY_TOKEN"
      ```

      The response includes `idea_id`, `title`, `description`, `updated_at`, and `latest_version_id`.

      ## Update the Idea

      Endpoint: `PATCH #{document_path}`

      Send exactly one of `description`, `content`, or `append`.

      ```bash
      curl -X PATCH #{base_url}#{document_path} \\
        -H "Authorization: Bearer $IDEA_FOUNDRY_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{"append":"New notes for the idea.","base_version_id":"LATEST_VERSION_ID","commit_message":"Add agent notes"}'
      ```

      Use `base_version_id` from the latest read when editing. A `409 Conflict` means the human or another agent changed the idea first; read again and retry from the latest document.

      ## Scope

      This token can read and update only this idea's document. It cannot access other ideas or settings.
    MARKDOWN
  end
end
