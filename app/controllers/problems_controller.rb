class ProblemsController < ApplicationController
  before_action :set_user
  before_action :set_problem, only: %i[destroy find link]

  def create
    @problem = @user.problems.build(params.require(:problem).permit(:title, :need))
    if @problem.save
      @problem.find_sources!
      Kb::TreeBroadcaster.call(@user)
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to kb_path(tab: "problems") }
    end
  end

  # Manual "Find on Wikipedia/Grokipedia".
  def find
    @problem.find_sources! unless @problem.status == "running"
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@problem, partial: "problems/problem", locals: { problem: @problem }) }
      format.html { redirect_to kb_path(tab: "problems") }
    end
  end

  # Link the problem's KB folder from an idea.
  def link
    idea = @user.ideas.find(params[:idea_id])
    idea.kb_links.find_or_create_by!(source_path: KbSource::NATIVE_PATH, relative_path: @problem.folder) do |l|
      l.entry_type = "dir"
      l.position = idea.kb_links.maximum(:position).to_i + 1
    end
    redirect_to kb_path(tab: "problems"), notice: "Linked to #{idea.title}."
  end

  # Removes the record only; the KB files stay (they are the source of truth).
  def destroy
    @problem.destroy
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@problem) }
      format.html { redirect_to kb_path(tab: "problems") }
    end
  end

  private

  def set_problem = @problem = @user.problems.find(params[:id])
end
