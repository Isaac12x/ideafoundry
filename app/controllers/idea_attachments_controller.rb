class IdeaAttachmentsController < ApplicationController
  before_action :set_user
  before_action :set_idea

  def create
    files = Array(params[:files]).compact_blank
    return render json: { error: "No files provided" }, status: :bad_request if files.empty?

    existing_ids = @idea.attachments_attachments.pluck(:id)
    new_attachments = []

    Idea.without_history_tracking do
      @idea.attachments.attach(files)
      @idea.reload

      new_attachments = @idea.attachments_attachments.where.not(id: existing_ids).order(:position, :created_at).to_a
      new_attachments.each do |a|
        next unless AttachmentOcrJob.ocr_supported?(a)
        a.update!(ocr_status: "queued")
        AttachmentOcrJob.perform_later(a.id)
      end
    end
    @idea.record_history!("Updated media", automatic: true) if new_attachments.any?

    html = new_attachments.map { |attachment|
      render_to_string(partial: "idea_attachments/item", locals: { attachment: attachment, idea: @idea })
    }.join

    render json: { success: true, html: html }
  end

  def destroy
    attachment = @idea.attachments_attachments.find(params[:id])
    attachment.purge
    head :no_content
  end

  def update
    attachment = @idea.attachments_attachments.find(params[:id])

    if params[:filename].present?
      attachment.blob.update!(filename: params[:filename])
    end

    if params[:file].present?
      position = attachment.position
      attachment.purge
      @idea.attachments.attach(params[:file])
      @idea.reload
      attachment = @idea.attachments_attachments.order(created_at: :desc).first
      attachment.update!(position: position)
    end

    html = render_to_string(partial: "idea_attachments/item", locals: { attachment: attachment, idea: @idea })
    render json: { success: true, html: html }
  end

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
