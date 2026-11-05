# "Attach to idea…" for a KB image (video screenshots, edited images, any PNG/JPG):
# copies the file into the idea's attachments, optionally also appended to its hero set.
class KbIdeaAttachmentsController < ApplicationController
  include KbFileLookup

  before_action :set_user

  def create
    file = locate_kb_file
    return render_error("The image is no longer available.", :not_found) unless file
    return render_error("Only images can be attached.") unless Kb::MediaTypes.kind_for(file[:abs]) == :image
    # Ideas feed AI tools; a private project's files must not leak into one.
    return render_error("Files in private projects can't be attached to ideas.", :forbidden) if private_kb_file?(file)

    idea = @user.ideas.find_by(id: params[:idea_id])
    return render_error("Pick an idea.") unless idea

    hero = ActiveModel::Type::Boolean.new.cast(params[:hero]) || false
    attachment = nil
    Idea.without_history_tracking do
      attachment = attach(idea, file[:abs])
      idea.hero_images.attach(attachment.blob) if hero
    end
    idea.record_history!("Updated media", automatic: true)

    render json: { idea: { id: idea.id, title: idea.title, url: idea_path(idea) }, hero: hero, attachment_id: attachment.id }, status: :created
  end

  private

  def attach(idea, abs)
    File.open(abs, "rb") do |io|
      idea.attachments.attach(io: io, filename: File.basename(abs), content_type: Kb::MediaTypes.mime_type_for(abs))
    end
    attachment = idea.attachments_attachments.order(:id).last
    if AttachmentOcrJob.ocr_supported?(attachment)
      attachment.update!(ocr_status: "queued")
      AttachmentOcrJob.perform_later(attachment.id)
    end
    attachment
  end

  def render_error(message, status = :unprocessable_content)
    render json: { error: message }, status: status
  end
end
