class IdeaEntriesController < ApplicationController
  before_action :set_user
  before_action :set_idea
  before_action :set_idea_entry, only: [:update, :destroy]

  def create
    attributes = idea_entry_params
    @kind = attributes[:kind].presence || User::IDEA_ENTRY_TABS.first
    @idea_entry = @idea.idea_entries.build(attributes)

    if @idea_entry.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to idea_path(@idea, anchor: @idea_entry.kind) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: entry_form_streams(@kind, @idea_entry), status: :unprocessable_content }
        format.html { redirect_to idea_path(@idea), alert: @idea_entry.errors.full_messages.join(", ") }
      end
    end
  end

  def update
    if @idea_entry.update(idea_entry_params.except(:kind))
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to idea_path(@idea, anchor: @idea_entry.kind) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: entry_form_streams(@idea_entry.kind, @idea_entry), status: :unprocessable_content }
        format.html { redirect_to idea_path(@idea), alert: @idea_entry.errors.full_messages.join(", ") }
      end
    end
  end

  def destroy
    kind = @idea_entry.kind
    @idea_entry.destroy
    @kind = kind

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to idea_path(@idea, anchor: kind) }
    end
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def set_idea_entry
    @idea_entry = @idea.idea_entries.find(params[:id])
  end

  def idea_entry_params
    permitted = params.require(:idea_entry).permit(:kind, :name, :url, :description)
    if permitted[:kind].present?
      permitted[:kind] = permitted[:kind].to_s
      permitted[:kind] = nil unless IdeaEntry.kinds.key?(permitted[:kind])
    end
    permitted
  end

  def entry_form_streams(kind, idea_entry)
    [
      turbo_stream.replace(
        "idea_entries_tab_#{@idea.id}_#{kind}",
        partial: "idea_entries/tab",
        locals: { idea: @idea, kind: kind, idea_entry: idea_entry }
      ),
      turbo_stream.replace(
        "idea_entry_summary_#{@idea.id}_#{kind}",
        partial: "idea_entries/card_summary",
        locals: { idea: @idea, kind: kind, idea_entry: idea_entry, open: true }
      )
    ]
  end
end
