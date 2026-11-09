# Links an idea to KB projects, folders and files. Created from the idea page.
class IdeaKbLinksController < ApplicationController
  include KbEntrySearch

  before_action :set_user
  before_action :set_idea, except: :search # search is idea-independent (also used by the new-idea form)

  def search
    # Blank query lists projects only, so the picker shows them on focus.
    query = params[:q].to_s.strip.downcase
    render json: { results: search_entries(query) }
  end

  def create
    source = KbSource.list(@user)[params[:src].to_i] unless params[:src].to_i.negative?
    entry = source && IdeaKbLink.resolve_entry(File.expand_path(source[:path]), params[:path])
    return head(:unprocessable_content) unless entry

    @idea.kb_links.find_or_create_by!(source_path: source[:path], relative_path: entry[:rel]) do |link|
      link.entry_type = entry[:type]
      link.position = @idea.kb_links.maximum(:position).to_i + 1
    end
    respond_section
  end

  def destroy
    @idea.kb_links.find(params[:id]).destroy
    respond_section
  end

  private

  def respond_section
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("idea_kb_links_#{@idea.id}",
                                                  partial: "ideas/kb_links", locals: { idea: @idea.reload })
      end
      format.html { redirect_to idea_path(@idea) }
    end
  end

  def set_user
    @user = User.first
  end

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end
end
