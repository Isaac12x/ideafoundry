class IdeaAgentTokensController < ApplicationController
  before_action :set_idea

  def create
    token = IdeaAgentToken.generate(
      idea: @idea,
      name: idea_agent_token_params[:name]
    )

    flash[:idea_agent_token] = token.raw_token
    flash[:idea_agent_token_idea_id] = @idea.id

    redirect_to @idea, notice: "Agent token created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @idea, alert: "Failed to create agent token: #{e.record.errors.full_messages.to_sentence}"
  end

  def destroy
    @idea.idea_agent_tokens.find(params[:id]).destroy!

    redirect_to @idea, notice: "Agent token revoked."
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def idea_agent_token_params
    params.require(:idea_agent_token).permit(:name)
  end
end
