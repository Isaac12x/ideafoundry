class NotesController < ApplicationController
  before_action :set_user
  before_action :set_idea
  before_action :set_note, only: [:destroy]

  def create
    @note = @idea.notes.build(note_params)

    if @note.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to idea_path(@idea, anchor: "notes") }
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_content }
        format.html { redirect_to idea_path(@idea, anchor: "notes"), alert: @note.errors.full_messages.join(", ") }
      end
    end
  end

  def destroy
    @note.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to idea_path(@idea, anchor: "notes") }
    end
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def set_note
    @note = @idea.notes.find(params[:id])
  end

  def note_params
    params.require(:note).permit(:body, :parent_note_id)
  end
end
