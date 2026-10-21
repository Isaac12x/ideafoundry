# "Why I saved this" note for any non-markdown KB file, stored in the sidecar
# "<file>.note.md" (Kb::Note). GET reads it, PATCH writes it (blank removes it).
# Path safety comes from KbFileLookup; writes refuse locked/locking projects like other KB writes.
class KbNotesController < ApplicationController
  include KbFileLookup

  before_action :set_user
  before_action :set_file

  def show
    render json: payload
  end

  def update
    case Kb::ProjectLock.write_block(@file[:root], @file[:rel])
    when :busy then return render json: { error: "This project is locking or unlocking. Try again in a moment." }, status: :conflict
    when :locked then return render json: { error: "Project is locked. Unlock it first." }, status: :conflict
    end

    Kb::Note.write!(@file[:abs], params[:text])
    Kb::TreeBroadcaster.call(@user) # busts the tree cache and refreshes the note mark
    render json: payload
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def set_file
    @file = locate_kb_file
    head(:not_found) unless @file && Kb::Note.eligible?(@file[:abs])
  end

  def payload
    text = Kb::Note.read(@file[:abs])
    { text: text, html: (Kb::MarkdownRenderer.render(text) if text.present?) }
  end
end
