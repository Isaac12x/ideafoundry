class IdeaAttachmentsController < ApplicationController
  before_action :set_user
  before_action :set_idea

  def reorder
    ids = Array(params[:attachment_ids]).map(&:to_i)
    attachments = @idea.attachments.attachments.where(id: ids).index_by(&:id)

    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, index|
        attachment = attachments.fetch(id)
        attachment.update!(position: index + 1)
      end
    end

    render json: { success: true, attachment_ids: @idea.ordered_attachments.map(&:id) }
  end

  def ocr
    attachment = @idea.attachments.attachments.find(params[:id])
    attachment.update!(ocr_status: "queued", ocr_error: nil)
    AttachmentOcrJob.perform_later(attachment.id)

    redirect_to edit_idea_path(@idea), notice: "OCR extraction queued for #{attachment.filename}."
  end

  private

  def set_user
    @user = User.first
  end

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end
end
